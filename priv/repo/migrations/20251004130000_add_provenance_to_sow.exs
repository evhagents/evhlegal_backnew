defmodule Evhlegalchat.Repo.Migrations.AddProvenanceToSow do
  use Ecto.Migration

  def change do
    alter table(:sow_deliverables) do
      add :ingest_timestamp, :utc_datetime_usec
      add :extractor_version, :string, size: 20
      add :model_versions, :map
    end

    alter table(:sow_milestones) do
      add :ingest_timestamp, :utc_datetime_usec
      add :extractor_version, :string, size: 20
      add :model_versions, :map
    end

    alter table(:sow_pricing_schedules) do
      add :ingest_timestamp, :utc_datetime_usec
      add :extractor_version, :string, size: 20
      add :model_versions, :map
    end

    alter table(:sow_rate_cards) do
      add :ingest_timestamp, :utc_datetime_usec
      add :extractor_version, :string, size: 20
      add :model_versions, :map
    end

    alter table(:sow_invoicing_terms) do
      add :ingest_timestamp, :utc_datetime_usec
      add :extractor_version, :string, size: 20
      add :model_versions, :map
    end
  end
end


