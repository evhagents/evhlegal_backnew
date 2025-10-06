defmodule Evhlegalchat.Enrich.SOWEnrichWorker do
  use Oban.Worker,
    queue: :ingest,
    max_attempts: 10,
    unique: [fields: [:args], keys: [:agreement_id], period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"agreement_id" => agreement_id}}) do
    counts = Evhlegalchat.Enrich.SOW.run(agreement_id)
    :telemetry.execute([:enrich, :sow, :done], counts, %{agreement_id: agreement_id})
    {:ok, counts}
  end
end


