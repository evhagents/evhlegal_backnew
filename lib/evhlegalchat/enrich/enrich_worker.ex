defmodule Evhlegalchat.Enrich.EnrichWorker do
  use Oban.Worker,
    queue: :ingest,
    max_attempts: 10,
    unique: [fields: [:args], keys: [:agreement_id], period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  import Ecto.Query
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Agreement

  @impl true
  def perform(%Oban.Job{args: %{"agreement_id" => agreement_id}}) do
    :telemetry.execute([:enrich, :start], %{}, %{agreement_id: agreement_id})

    Repo.transaction(fn ->
      # lightweight advisory lock via pg_try_advisory_xact_lock on agreement_id
      Repo.query!("SELECT pg_try_advisory_xact_lock($1)", [agreement_id])

      agreement = Repo.get!(Agreement, agreement_id)

      clauses_exist =
        from(c in "clauses", where: c.agreement_id == ^agreement_id)
        |> Repo.exists?()

      if not clauses_exist do
        Repo.rollback({:discard, :no_clauses})
      end

      case agreement.doc_type do
        :NDA ->
          Oban.insert!(Evhlegalchat.Enrich.NDAEnrichWorker.new(%{"agreement_id" => agreement_id}))
        :SOW ->
          Oban.insert!(Evhlegalchat.Enrich.SOWEnrichWorker.new(%{"agreement_id" => agreement_id}))
        other ->
          Logger.warning("Unknown doc_type", doc_type: other)
          Repo.rollback({:discard, :unknown_doc_type})
      end

      {:ok, :enqueued}
    end)
    |> case do
      {:ok, {:ok, :enqueued}} -> {:ok, :enqueued}
      {:error, {:discard, reason}} -> {:discard, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end


