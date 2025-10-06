defmodule Evhlegalchat.Repo.Migrations.CreateMappingLayer do
  use Ecto.Migration

  def change do
    # mapping_status enum
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mapping_status') THEN
        CREATE TYPE mapping_status AS ENUM ('proposed','applied','rejected','superseded');
      END IF;
    END$$;
    """, "DROP TYPE IF EXISTS mapping_status"

    # review_state enum
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'review_state') THEN
        CREATE TYPE review_state AS ENUM ('open','in_progress','resolved');
      END IF;
    END$$;
    """, "DROP TYPE IF EXISTS review_state"

    create_if_not_exists table(:extracted_facts, primary_key: false) do
      add :fact_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false

      add :target_table, :string, size: 64, null: false
      add :target_pk_name, :string, size: 64, null: false
      add :target_pk_value, :integer, null: false
      add :target_column, :string, size: 64, null: false

      add :raw_value, :text
      add :normalized_value, :text
      add :normalized_numeric, :decimal
      add :normalized_unit, :string, size: 32

      add :evidence_clause_id, references(:clauses, column: :clause_id)
      add :evidence_start_char, :integer
      add :evidence_end_char, :integer
      add :evidence_start_page, :integer
      add :evidence_end_page, :integer

      add :confidence, :decimal, precision: 4, scale: 3, null: false
      add :status, :mapping_status, null: false, default: "proposed"
      add :reason, :text

      add :extractor, :string, size: 64
      add :extractor_version, :string, size: 16

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'extracted_facts' 
          AND column_name = 'fact_id' 
          AND is_identity = 'YES'
      ) THEN
        ALTER TABLE extracted_facts ALTER COLUMN fact_id ADD GENERATED ALWAYS AS IDENTITY;
      END IF;
    END$$;
    """

    create_if_not_exists index(:extracted_facts, [:agreement_id], name: :idx_facts_agreement)
    create_if_not_exists index(:extracted_facts, [:target_table, :target_pk_value, :target_column], name: :idx_facts_target)
    create_if_not_exists index(:extracted_facts, [:status], name: :idx_facts_status)
    create_if_not_exists index(:extracted_facts, [:confidence], name: :idx_facts_conf)

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 
        FROM pg_indexes 
        WHERE schemaname = 'public' AND indexname = 'idx_facts_dedupe'
      ) THEN
        CREATE UNIQUE INDEX idx_facts_dedupe ON extracted_facts
        (target_table, target_pk_value, target_column, coalesce(normalized_value, raw_value), coalesce(evidence_clause_id, 0));
      END IF;
    END$$;
    """

    create_if_not_exists table(:review_tasks, primary_key: false) do
      add :review_task_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :fact_id, references(:extracted_facts, column: :fact_id, on_delete: :delete_all)
      add :title, :string, size: 200, null: false
      add :details, :map, null: false, default: %{}
      add :state, :review_state, null: false, default: "open"
      add :assignee_user_id, :integer
      add :resolution, :text
      add :resolved_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'review_tasks' 
          AND column_name = 'review_task_id' 
          AND is_identity = 'YES'
      ) THEN
        ALTER TABLE review_tasks ALTER COLUMN review_task_id ADD GENERATED ALWAYS AS IDENTITY;
      END IF;
    END$$;
    """

    create_if_not_exists index(:review_tasks, [:agreement_id, :state], name: :idx_review_agreement)
    create_if_not_exists index(:review_tasks, [:fact_id], name: :idx_review_fact)

    create_if_not_exists table(:field_audit, primary_key: false) do
      add :field_audit_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false

      add :target_table, :string, size: 64, null: false
      add :target_pk_name, :string, size: 64, null: false
      add :target_pk_value, :integer, null: false
      add :target_column, :string, size: 64, null: false

      add :old_value, :text
      add :new_value, :text
      add :fact_id, references(:extracted_facts, column: :fact_id)
      add :actor_user_id, :integer
      add :action, :string, size: 32, null: false
      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create_if_not_exists index(:field_audit, [:target_table, :target_pk_value, :target_column], name: :idx_audit_target)

    # updated_at triggers
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_proc WHERE proname = 'set_updated_at'
      ) THEN
        CREATE OR REPLACE FUNCTION set_updated_at()
        RETURNS trigger AS $$
        BEGIN
          NEW.updated_at := now();
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      END IF;
    END$$;
    """

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'extracted_facts_set_updated_at'
      ) THEN
        CREATE TRIGGER extracted_facts_set_updated_at
        BEFORE UPDATE ON extracted_facts
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'review_tasks_set_updated_at'
      ) THEN
        CREATE TRIGGER review_tasks_set_updated_at
        BEFORE UPDATE ON review_tasks
        FOR EACH ROW EXECUTE PROCEDURE set_updated_at();
      END IF;
    END$$;
    """
  end
end



