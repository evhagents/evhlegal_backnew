defmodule Evhlegalchat.Repo.Migrations.CreateAgreementLinks do
  use Ecto.Migration

  def change do
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'agreement_link_type') THEN
        CREATE TYPE agreement_link_type AS ENUM ('supersedes','amends','related');
      END IF;
    END$$;
    """, "DROP TYPE IF EXISTS agreement_link_type"

    create_if_not_exists table(:agreement_links, primary_key: false) do
      add :agreement_link_id, :integer, primary_key: true
      add :from_agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :to_agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :link_type, :agreement_link_type, null: false
      add :notes, :text
      timestamps(type: :utc_datetime_usec)
    end

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'agreement_links' 
          AND column_name = 'agreement_link_id' 
          AND is_identity = 'YES'
      ) THEN
        ALTER TABLE agreement_links ALTER COLUMN agreement_link_id ADD GENERATED ALWAYS AS IDENTITY;
      END IF;
    END$$;
    """

    create_if_not_exists index(:agreement_links, [:from_agreement_id])
    create_if_not_exists index(:agreement_links, [:to_agreement_id])
    create_if_not_exists unique_index(:agreement_links, [:from_agreement_id, :to_agreement_id, :link_type], name: :agreement_links_uq_pair)
  end
end


