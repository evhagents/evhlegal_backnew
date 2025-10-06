defmodule Evhlegalchat.Mapping.Review do
  @moduledoc """
  Review workflow helpers for opening/updating review tasks.
  """
  import Ecto.Query
  alias Ecto.Multi
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Mapping.{ReviewTask, ExtractedFact, FieldAudit}
  alias Evhlegalchat.{Agreement}
  alias Evhlegalchat.Mapping.Router

  @doc """
  Open or update a review task under the same agreement and target.
  Keeps one task and appends proposals in details.
  """
  def open_or_update_task!(%ExtractedFact{} = fact, extra \\ %{}) do
    details_payload = %{
      target: %{table: fact.target_table, column: fact.target_column, pk: %{name: fact.target_pk_name, value: fact.target_pk_value}},
      proposal: %{
        raw: fact.raw_value,
        normalized: fact.normalized_value,
        normalized_numeric: fact.normalized_numeric,
        normalized_unit: fact.normalized_unit,
        confidence: fact.confidence,
        evidence_clause_id: fact.evidence_clause_id
      }
    }
    |> Map.merge(extra)

    title = "Confirm #{fact.target_column}: #{fact.normalized_value || fact.raw_value}"

    q = from r in ReviewTask,
      where: r.agreement_id == ^fact.agreement_id and r.state in [^:open, ^:in_progress],
      where: fragment("details->'target'->>'table' = ?", ^fact.target_table),
      where: fragment("details->'target'->>'column' = ?", ^fact.target_column),
      limit: 1

    Multi.new()
    |> Multi.run(:existing, fn _repo, _ -> {:ok, Repo.one(q)} end)
    |> Multi.run(:task, fn repo, %{existing: existing} ->
      case existing do
        nil ->
          %ReviewTask{}
          |> ReviewTask.changeset(%{agreement_id: fact.agreement_id, fact_id: fact.fact_id, title: title, details: details_payload})
          |> repo.insert()

        %ReviewTask{} = task ->
          new_details = Map.update(task.details || %{}, "proposals", [details_payload], fn list -> List.wrap(list) ++ [details_payload] end)
          task
          |> ReviewTask.changeset(%{fact_id: fact.fact_id, details: new_details})
          |> repo.update()
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{task: task}} ->
        :telemetry.execute([:mapping, :fact, :review_opened], %{count: 1}, %{agreement_id: fact.agreement_id, fact_id: fact.fact_id})
        task
      {:error, _op, reason, _} -> raise reason
    end
  end

  @doc """
  Resolve a review task by approving or rejecting the candidate fact.

  decision: :approve | :reject
  opts: %{actor_user_id: integer | nil, resolution: String.t() | nil}
  """
  def resolve_task!(task_id_or_struct, decision, opts \\ %{}) do
    actor_user_id = Map.get(opts, :actor_user_id)
    resolution_note = Map.get(opts, :resolution) || to_string(decision)

    Multi.new()
    |> Multi.run(:task, fn _repo, _ ->
      case task_id_or_struct do
        %ReviewTask{} = t -> {:ok, t}
        id when is_integer(id) ->
          case Repo.get(ReviewTask, id) do
            nil -> {:error, :not_found}
            t -> {:ok, t}
          end
      end
    end)
    |> Multi.run(:fact, fn _repo, %{task: task} ->
      case task.fact_id && Repo.get(ExtractedFact, task.fact_id) do
        %ExtractedFact{} = fact -> {:ok, fact}
        _ -> {:ok, nil}
      end
    end)
    |> Multi.run(:apply_or_mark, fn _repo, %{task: task, fact: fact} ->
      case {decision, fact} do
        {:approve, %ExtractedFact{} = f} ->
          case Router.route_and_apply(f) do
            {:ok, result} -> {:ok, {:applied, result}}
            {:error, reason} -> {:error, reason}
            {:error, _op, reason, _} -> {:error, reason}
          end
        {:approve, nil} -> {:error, :no_fact}
        {:reject, %ExtractedFact{} = f} ->
          Repo.update(ExtractedFact.changeset(f, %{status: :rejected, reason: resolution_note}))
        {:reject, nil} -> {:ok, {:rejected, :no_fact}}
      end
    end)
    |> Multi.run(:audit_override, fn _repo, %{task: task, fact: fact, apply_or_mark: apply_or_mark} ->
      # Append-only human audit entry
      case {decision, fact, apply_or_mark} do
        {:approve, %ExtractedFact{} = f, {:applied, result_map}} ->
          # Try to reuse old/new values from the system audit if present
          {old_val, new_val} = extract_old_new_from_result(result_map) || {f.normalized_value || f.raw_value, f.normalized_value || f.raw_value}
          _ = Repo.insert(FieldAudit.changeset(%FieldAudit{}, %{
            agreement_id: f.agreement_id,
            target_table: f.target_table,
            target_pk_name: f.target_pk_name,
            target_pk_value: f.target_pk_value,
            target_column: f.target_column,
            old_value: encode_scalar(old_val),
            new_value: encode_scalar(new_val),
            fact_id: f.fact_id,
            actor_user_id: actor_user_id,
            action: "override",
            created_at: DateTime.utc_now()
          }))
          {:ok, :audited}
        {:reject, %ExtractedFact{} = f, _} ->
          # Record rejection decision
          _ = Repo.insert(FieldAudit.changeset(%FieldAudit{}, %{
            agreement_id: f.agreement_id,
            target_table: f.target_table,
            target_pk_name: f.target_pk_name,
            target_pk_value: f.target_pk_value,
            target_column: f.target_column,
            old_value: nil,
            new_value: nil,
            fact_id: f.fact_id,
            actor_user_id: actor_user_id,
            action: "reject",
            created_at: DateTime.utc_now()
          }))
          {:ok, :audited}
        _ -> {:ok, :skipped}
      end
    end)
    |> Multi.update(:resolve_task, fn %{task: task} ->
      ReviewTask.changeset(task, %{state: :resolved, resolution: resolution_note, resolved_at: DateTime.utc_now()})
    end)
    |> Multi.run(:maybe_update_agreement, fn _repo, %{task: task} ->
      open_count = from(r in ReviewTask, where: r.agreement_id == ^task.agreement_id and r.state in [^:open, ^:in_progress]) |> Repo.aggregate(:count)
      if open_count == 0 do
        q = from(a in Agreement, where: a.id == ^task.agreement_id or a.agreement_id == ^task.agreement_id)
        Repo.update_all(q, set: [review_status: :approved])
        {:ok, :approved}
      else
        {:ok, :pending}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{resolve_task: task}} ->
        _ = Evhlegalchat.Events.emit("review.resolved", %{review_task_id: task.review_task_id, agreement_id: task.agreement_id, decision: decision})
        {:ok, task}
      {:error, _op, reason, _} -> {:error, reason}
    end
  end

  defp extract_old_new_from_result(%{audit: %FieldAudit{} = audit}), do: {audit.old_value, audit.new_value}
  defp extract_old_new_from_result(_), do: nil

  defp encode_scalar(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_scalar(v) when is_binary(v) or is_nil(v), do: v
  defp encode_scalar(v) when is_integer(v), do: Integer.to_string(v)
  defp encode_scalar(%Decimal{} = d), do: Decimal.to_string(d)
  defp encode_scalar(v), do: to_string(v)
end


