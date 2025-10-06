defmodule Evhlegalchat.Mapping.WorkerIntegrationTest do
  use Evhlegalchat.DataCase, async: false
  import Ecto.Query
  alias Evhlegalchat.{Repo, Agreement}
  alias Evhlegalchat.Mapping.{ExtractedFact}

  setup do
    {:ok, ag} =
      %Agreement{}
      |> Agreement.new_changeset(%{
        doc_type: :NDA,
        agreement_title: "Test A",
        source_file_name: "a.pdf",
        source_hash: String.duplicate("a", 64),
        ingest_timestamp: DateTime.utc_now(),
        extractor_version: "0.0.1"
      })
      |> Repo.insert()

    %{agreement_id: ag.id || ag.agreement_id}
  end

  test "high confidence applies and audits", %{agreement_id: agreement_id} do
    {:ok, fact} =
      %ExtractedFact{}
      |> ExtractedFact.changeset(%{
        agreement_id: agreement_id,
        target_table: "agreements",
        target_pk_name: "agreement_id",
        target_pk_value: agreement_id,
        target_column: "governing_law",
        raw_value: "State of California",
        normalized_value: "California",
        confidence: Decimal.new("0.95")
      })
      |> Repo.insert()

    :ok = Evhlegalchat.Mapping.Worker.perform(%Oban.Job{args: %{"agreement_id" => agreement_id}})

    ag = Repo.get(Agreement, agreement_id)
    assert ag.governing_law == "California"
  end
end



