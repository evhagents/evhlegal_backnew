defmodule Evhlegalchat.Repo.Migrations.CreateStagingUploads do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:staging_uploads) do
      add :status, :string, null: false, default: "uploaded"
      add :scan_status, :string, null: false, default: "skipped"
      add :source_hash, :string, size: 64, null: false
      add :storage_key, :string, size: 512, null: false
      add :content_type_detected, :string, size: 128, null: false
      add :original_filename, :string, size: 255, null: false
      add :byte_size, :bigint, null: false
      add :rejection_reason, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:staging_uploads, [:source_hash])
    create_if_not_exists index(:staging_uploads, [:status])
    create_if_not_exists index(:staging_uploads, [:storage_key])
    create_if_not_exists index(:staging_uploads, [:inserted_at])

    # Create function to update updated_at
    execute """
    CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
    END;
    $$ language 'plpgsql';
    """, "DROP FUNCTION IF EXISTS update_updated_at_column()"


    # Create trigger to automatically update updated_at
    execute "DROP TRIGGER IF EXISTS update_staging_uploads_updated_at ON staging_uploads",""
    
    execute """
    CREATE TRIGGER update_staging_uploads_updated_at 
    BEFORE UPDATE ON staging_uploads 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();
    """, "DROP TRIGGER IF EXISTS update_staging_uploads_updated_at ON staging_uploads"
  end
end
