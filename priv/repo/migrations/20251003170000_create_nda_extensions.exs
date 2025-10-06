defmodule Evhlegalchat.Repo.Migrations.CreateNdaExtensions do
  use Ecto.Migration

  def change do
    execute """
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'nda_clause_key') THEN
    CREATE TYPE nda_clause_key AS ENUM (
      'definition_confidential_information',
      'use_restrictions',
      'term_duration',
      'return_or_destroy',
      'injunctive_relief',
      'governing_law',
      'venue',
      'no_license'
    );
  END IF;
END $$;
""", "DROP TYPE IF EXISTS nda_clause_key"

    create_if_not_exists table(:nda_parties, primary_key: false) do
      add :nda_party_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :role, :string, size: 64, null: false
      add :display_name, :string, size: 255, null: false
      add :legal_name_norm, :string, size: 255
      add :evidence_clause_id, references(:clauses, column: :clause_id)
      timestamps(type: :utc_datetime_usec)
    end

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'nda_parties' 
        AND column_name = 'nda_party_id' 
        AND is_identity = 'YES'
      ) THEN
        ALTER TABLE nda_parties ALTER COLUMN nda_party_id ADD GENERATED ALWAYS AS IDENTITY;
      END IF;
    END $$;
 """
 create_if_not_exists unique_index(:nda_parties, [:agreement_id, :display_name, :evidence_clause_id])

    create_if_not_exists table(:nda_carveouts, primary_key: false) do
      add :carveout_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :label, :string, size: 128
      add :text, :text, null: false
      add :evidence_clause_id, references(:clauses, column: :clause_id)
      add :confidence, :decimal, precision: 4, scale: 3
      timestamps(type: :utc_datetime_usec)
    end

    execute """
        DO $$
        BEGIN
          IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'nda_carveouts' AND column_name = 'carveout_id' AND is_identity = 'YES'
          ) THEN
            ALTER TABLE nda_carveouts ALTER COLUMN carveout_id ADD GENERATED ALWAYS AS IDENTITY;
          END IF;
        END $$;
    """
    create_if_not_exists unique_index(:nda_carveouts, [:agreement_id, :text, :evidence_clause_id])

    create_if_not_exists table(:nda_key_clauses, primary_key: false) do
      add :nda_key_clause_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :key, :nda_clause_key, null: false
      add :value_text, :text
      add :value_numeric, :decimal
      add :value_unit, :string, size: 32
      add :evidence_clause_id, references(:clauses, column: :clause_id)
      add :confidence, :decimal, precision: 4, scale: 3
      timestamps(type: :utc_datetime_usec)
    end

    execute "ALTER TABLE nda_key_clauses ALTER COLUMN nda_key_clause_id ADD GENERATED ALWAYS AS IDENTITY"

    create_if_not_exists unique_index(:nda_key_clauses, [:agreement_id, :key])

    create_if_not_exists table(:nda_signatures, primary_key: false) do
      add :nda_signature_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :signer_name, :string, size: 255
      add :signer_title, :string, size: 255
      add :party_name, :string, size: 255
      add :signed_date, :date
      add :evidence_clause_id, references(:clauses, column: :clause_id)
      add :confidence, :decimal, precision: 4, scale: 3
      timestamps(type: :utc_datetime_usec)
    end

    execute "ALTER TABLE nda_signatures ALTER COLUMN nda_signature_id ADD GENERATED ALWAYS AS IDENTITY"
    create_if_not_exists unique_index(:nda_signatures, [:agreement_id, :signer_name, :signer_title, :signed_date, :evidence_clause_id])

    # Optional light-weight review flags
    create_if_not_exists table(:review_flags) do
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :entity, :string, null: false
      add :reason, :string, null: false
      add :evidence_clause_id, references(:clauses, column: :clause_id)
      add :details, :map, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:review_flags, [:agreement_id])
    create_if_not_exists unique_index(:review_flags, [:agreement_id, :entity, :reason, :evidence_clause_id])
  end
end


