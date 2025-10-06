defmodule Evhlegalchat.Mapping.Worker do
  @moduledoc """
  Oban worker consuming batches of proposed facts per agreement.
  """
  use Oban.Worker,
    queue: :ingest,
    max_attempts: 10,
    unique: [fields: [:args], keys: [:agreement_id], period: 900, states: [:available, :scheduled, :executing, :retryable]]

  import Ecto.Query
  alias Ecto.Multi
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Mapping.{ExtractedFact, Config, Review, Conflicts, Router}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"agreement_id" => agreement_id} = args}) do
    subset = Map.get(args, "target", nil)

    Repo.transaction(fn ->
      # Advisory lock per agreement
      Repo.query!("select pg_advisory_xact_lock($1)", [agreement_id])

      facts = load_proposed_facts(agreement_id, subset)
      conf = Config.fetch()

      results = Enum.map(facts, fn fact ->
        decision = evaluate_fact(fact, conf)
        emit(:evaluated, %{agreement_id: agreement_id, target: {fact.target_table, fact.target_column}, confidence: fact.confidence, decision: decision})
        case decision do
          :apply ->
            case Router.route_and_apply(fact) do
              {:ok, %{audit: audit}} ->
                emit(:applied, %{audit_id: audit.field_audit_id})
                {:applied, fact.fact_id}
              {:ok, _} -> {:applied, fact.fact_id}
              {:error, reason} -> reject!(fact, "apply_error: #{inspect(reason)}")
              {:error, _op, reason, _} -> reject!(fact, "apply_error: #{inspect(reason)}")
            end
          :review ->
            Review.open_or_update_task!(fact)
            maybe_mark_agreement_needs_review(fact)
            {:review, fact.fact_id}
          :reject ->
            reject!(fact, "below_threshold")
            {:rejected, fact.fact_id}
          {:supersede, old_fact} ->
            supersede!(old_fact)
            case Router.route_and_apply(fact) do
              {:ok, _} -> {:applied, fact.fact_id}
              other -> other
            end
        end
      end)

      emit(:batch_completed, %{agreement_id: agreement_id, counts: Enum.frequencies_by(results, &elem(&1, 0))})
      :ok
    end)
  end

  defp load_proposed_facts(agreement_id, nil) do
    from(f in ExtractedFact, where: f.agreement_id == ^agreement_id and f.status == ^:proposed)
    |> Repo.all()
  end
  defp load_proposed_facts(agreement_id, {table, column}) do
    from(f in ExtractedFact,
      where: f.agreement_id == ^agreement_id and f.status == ^:proposed and f.target_table == ^table and f.target_column == ^column
    ) |> Repo.all()
  end

  defp evaluate_fact(fact, conf) do
    auto = conf[:auto_commit_threshold]
    review = conf[:review_threshold]

    # check conflicts against latest applied for the same target
    existing = latest_applied_for_target(fact)
    decision =
      cond do
        Decimal.cmp(Decimal.new(fact.confidence), Decimal.new(auto)) in [:gt, :eq] ->
          Conflicts.decide(fact, existing)
        Decimal.cmp(Decimal.new(fact.confidence), Decimal.new(review)) in [:gt, :eq] ->
          :review
        true -> :reject
      end

    case decision do
      :apply -> :apply
      :keep_existing -> :reject
      :supersede_old -> {:supersede, existing}
      other -> other
    end
  end

  defp latest_applied_for_target(fact) do
    from(f in ExtractedFact,
      where: f.target_table == ^fact.target_table and f.target_pk_value == ^fact.target_pk_value and f.target_column == ^fact.target_column and f.status == ^:applied,
      order_by: [desc: f.updated_at],
      limit: 1
    ) |> Repo.one()
  end

  defp reject!(%ExtractedFact{} = fact, reason) do
    {:ok, _} = Repo.update(ExtractedFact.changeset(fact, %{status: :rejected, reason: reason}))
    emit(:rejected, %{fact_id: fact.fact_id})
    {:rejected, fact.fact_id}
  end

  defp maybe_mark_agreement_needs_review(fact) do
    # if protected columns are involved, mark agreement review status
    case fact.target_table do
      "agreements" ->
        from(a in Evhlegalchat.Agreement, where: a.id == ^fact.agreement_id or a.agreement_id == ^fact.agreement_id)
        |> Repo.update_all(set: [review_status: :needs_review])
        :ok
      _ -> :ok
    end
  end

  defp supersede!(%ExtractedFact{} = old) do
    {:ok, _} = Repo.update(ExtractedFact.changeset(old, %{status: :superseded}))
    :ok
  end

  defp emit(:evaluated, meta), do: :telemetry.execute([:mapping, :fact, :evaluated], %{count: 1}, meta)
  defp emit(:applied, meta), do: :telemetry.execute([:mapping, :fact, :applied], %{count: 1}, meta)
  defp emit(:review_opened, meta), do: :telemetry.execute([:mapping, :fact, :review_opened], %{count: 1}, meta)
  defp emit(:rejected, meta), do: :telemetry.execute([:mapping, :fact, :rejected], %{count: 1}, meta)
  defp emit(:batch_completed, meta), do: :telemetry.execute([:mapping, :batch, :completed], %{count: 1}, meta)
end


