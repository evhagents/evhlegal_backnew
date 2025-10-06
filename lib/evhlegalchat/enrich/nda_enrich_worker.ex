defmodule Evhlegalchat.Enrich.NDAEnrichWorker do
  use Oban.Worker,
    queue: :ingest,
    max_attempts: 10,
    unique: [fields: [:args], keys: [:agreement_id], period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  alias Evhlegalchat.Repo
  alias Evhlegalchat.{Review}
  alias Evhlegalchat.NDA.{Party, Carveout, KeyClause, Signature}
  import Ecto.Query

  @impl true
  def perform(%Oban.Job{args: %{"agreement_id" => agreement_id}}) do
    {counts, flagged?} = Evhlegalchat.Enrich.NDA.run(agreement_id)

    :telemetry.execute([:enrich, :nda, :done], counts, %{agreement_id: agreement_id})

    if flagged? do
      from(a in "agreements", where: a.id == ^agreement_id and a.review_status != "approved")
      |> Repo.update_all(set: [review_status: "needs_review", updated_at: DateTime.utc_now()])
    end

    {:ok, counts}
  end
end


