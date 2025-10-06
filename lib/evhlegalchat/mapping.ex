defmodule Evhlegalchat.Mapping do
  @moduledoc """
  Public API to capture facts and enqueue mapping worker.
  """
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Mapping.ExtractedFact

  def capture_fact(attrs) when is_map(attrs) do
    cs = ExtractedFact.changeset(%ExtractedFact{}, attrs)
    with {:ok, fact} <- Repo.insert(cs, on_conflict: :nothing) do
      enqueue_worker(fact.agreement_id)
      {:ok, fact}
    end
  end

  def enqueue_worker(agreement_id) do
    Oban.insert!(Evhlegalchat.Mapping.Worker.new(%{agreement_id: agreement_id}))
  end
end



