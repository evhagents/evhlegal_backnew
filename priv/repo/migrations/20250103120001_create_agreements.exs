defmodule Evhlegalchat.Repo.Migrations.CreateAgreements do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:agreements, primary_key: false) do
      add :agreement_id, :serial, primary_key: true
      add :doc_type, :string, size: 10, null: false
      add :agreement_title, :string, size: 255, null: false
      add :effective_date, :date
      add :governing_law, :string, size: 100
      add :venue, :string, size: 100
      add :term_length_months, :integer
      add :early_termination_allowed, :boolean, default: false
      add :early_termination_notice, :string, size: 100
      add :survival_period_months, :integer
      add :status, :string, size: 20, null: false, default: "draft"
      add :transaction_context, :map, default: %{}
      add :source_file_name, :string, size: 255, null: false
      add :source_hash, :string, size: 64, null: false
      add :ingest_timestamp, :utc_datetime_usec, null: false
      add :extractor_version, :string, size: 20, null: false
      add :model_versions, :map, default: %{}
      add :review_status, :string, size: 20, null: false, default: "unreviewed"
      add :reviewer_notes, :text
      add :storage_key, :string, size: 512

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:agreements, [:source_hash])
    create_if_not_exists index(:agreements, [:doc_type])
    create_if_not_exists index(:agreements, [:status])
    create_if_not_exists index(:agreements, [:review_status])
    create_if_not_exists index(:agreements, [:effective_date])
    create_if_not_exists index(:agreements, [:ingest_timestamp])
  end
end
