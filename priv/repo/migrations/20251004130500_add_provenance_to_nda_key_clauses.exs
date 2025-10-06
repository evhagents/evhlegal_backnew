defmodule Evhlegalchat.Repo.Migrations.AddProvenanceToNdaKeyClauses do
  use Ecto.Migration

  def change do
    alter table(:nda_key_clauses) do
      add :ingest_timestamp, :utc_datetime_usec
      add :extractor_version, :string, size: 20
      add :model_versions, :map
    end
  end
end


