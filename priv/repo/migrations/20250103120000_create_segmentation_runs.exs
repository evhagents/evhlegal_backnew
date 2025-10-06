defmodule Evhlegalchat.Repo.Migrations.CreateSegmentationRuns do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:segmentation_runs) do
      add :staging_upload_id, :integer, null: false
      add :segmentation_major, :integer, null: false
      add :segmentation_minor, :integer, null: false  
      add :segmentation_patch, :integer, null: false
      add :status, :string, null: false, default: "started"
      add :text_concat_key, :string, size: 512, null: false
      add :pages_jsonl_key, :string, size: 512, null: false
      add :segments_artifact_key, :string, size: 512
      add :metrics, :map, null: false, default: %{}
      add :accepted_count, :integer, default: 0
      add :suppressed_count, :integer, default: 0
      add :mean_conf_boundary, :float, default: 0.0
      add :needs_review_reason, :text
      add :preview_key, :string, size: 512

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:segmentation_runs, [:staging_upload_id, :segmentation_major, :segmentation_minor, :segmentation_patch])
    create_if_not_exists index(:segmentation_runs, [:status])
    create_if_not_exists index(:segmentation_runs, [:staging_upload_id])
    create_if_not_exists index(:segmentation_runs, [:inserted_at])

    create_if_not_exists table(:clauses) do
      add :segmentation_run_id, :integer, null: false
      add :staging_upload_id, :integer, null: false
      add :agreement_id, :integer
      add :ordinal, :integer, null: false
      add :number_label, :string, size: 50
      add :number_label_normalized, :string, size: 50
      add :heading_text, :string, size: 511
      add :start_char, :integer, null: false
      add :end_char, :integer, null: false
      add :start_page, :integer, null: false
      add :end_page, :integer, null: false
      add :text_snippet, :string, size: 200, null: false
      add :detected_style, :string, size: 50, null: false
      add :confidence_boundary, :float, default: 0.0
      add :confidence_heading, :float, default: 0.0
      add :anomaly_flags, :map, default: %{}
      add :needs_review, :boolean, default: false
      add :human_verified, :boolean, default: false
      add :suppressed, :boolean, default: false
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:clauses, [:segmentation_run_id])
    create_if_not_exists index(:clauses, [:staging_upload_id])
    create_if_not_exists index(:clauses, [:agreement_id])
    create_if_not_exists unique_index(:clauses, [:staging_upload_id, :ordinal], where: "deleted_at IS NULL")
    create_if_not_exists index(:clauses, [:start_char, :end_char])
    create_if_not_exists index(:clauses, [:confidence_boundary])
    create_if_not_exists index(:clauses, [:needs_review])
    create_if_not_exists index(:clauses, [:human_verified])

    create_if_not_exists table(:segmentation_events) do
      add :segmentation_run_id, :integer, null: false
      add :event_type, :string, size: 50, null: false
      add :event_level, :string, size: 20, null: false, default: "info"
      add :detail, :map, null: false, default: %{}
      add :created_at, :utc_datetime_usec, null: false
    end

    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'segmentation_events' AND column_name = 'segmentation_run_id'
      ) THEN
        CREATE INDEX IF NOT EXISTS segmentation_events_segmentation_run_id_index ON segmentation_events(segmentation_run_id);
      END IF;
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'segmentation_events' AND column_name = 'event_type'
      ) THEN
        CREATE INDEX IF NOT EXISTS segmentation_events_event_type_index ON segmentation_events(event_type);
      END IF;
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'segmentation_events' AND column_name = 'event_level'
      ) THEN
        CREATE INDEX IF NOT EXISTS segmentation_events_event_level_index ON segmentation_events(event_level);
      END IF;
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'segmentation_events' AND column_name = 'created_at'
      ) THEN
        CREATE INDEX IF NOT EXISTS segmentation_events_created_at_index ON segmentation_events(created_at);
      END IF;
    END
    $$;
    """
  end
end
