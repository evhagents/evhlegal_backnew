defmodule Evhlegalchat.Ingest.StagingService do
  @moduledoc """
  Service for staging file uploads with deduplication.
  
  Handles the creation and management of staging upload records,
  ensuring idempotency based on SHA256 source hash.
  """

  require Logger
  import Ecto.Query
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Ingest.{StagingUpload, FileId, AV}
  alias Evhlegalchat.Storage.Local
  alias Oban

  @doc """
  Stages an uploaded file with deduplication.
  
  Returns {:ok, staging_upload} or {:error, reason}.
  """
  def stage_upload(file_path, original_filename, metadata \\ %{}) do
    Logger.metadata(action: :stage_upload, filename: original_filename)
    
    with {:ok, source_hash, content_type} <- FileId.identify_file(file_path, original_filename),
         {:ok, byte_size} <- get_file_size(file_path),
         {:ok, scan_result} <- perform_scan(file_path),
         result <- find_or_create_staging(source_hash, original_filename, content_type, byte_size, metadata, file_path, scan_result) do
      case result do
        {:ok, {:created, staging_upload}} ->
          emit_telemetry(:upload_staged, %{staging_upload_id: staging_upload.staging_upload_id})
          {:ok, staging_upload}
        {:ok, {:existing, staging_upload}} ->
          emit_telemetry(:upload_duplicate_detected, %{staging_upload_id: staging_upload.staging_upload_id})
          {:ok, staging_upload}
        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Finds an existing staging upload by source hash or creates a new one.
  """
  def find_or_create_staging(source_hash, original_filename, content_type, byte_size, metadata, temp_path, scan_result) do
    case Repo.get_by(StagingUpload, source_hash: source_hash) do
      nil ->
        create_staging(source_hash, original_filename, content_type, byte_size, metadata, temp_path, scan_result)
      existing ->
        {:ok, {:existing, existing}}
    end
  end

  @doc """
  Creates a new staging upload record.
  """
  def create_staging(source_hash, original_filename, content_type, byte_size, metadata, temp_path, scan_result) do
    storage_key = generate_storage_key(source_hash, content_type)
    storage = Local.new()

    scan_status = case scan_result do
      :clean -> :clean
      :infected -> :infected
      :skipped -> :skipped
    end

    attrs = %{
      source_hash: source_hash,
      storage_key: storage_key,
      content_type_detected: content_type,
      original_filename: original_filename,
      byte_size: byte_size,
      metadata: Map.put(metadata, :scanned_at, DateTime.utc_now()),
      scan_status: scan_status,
      status: if(scan_status == :infected, do: :rejected, else: :ready_for_extraction)
    }

    rejection_reason = if scan_status == :infected, do: "File flagged as malicious by antivirus", else: nil

    attrs = if rejection_reason, do: Map.put(attrs, :rejection_reason, rejection_reason), else: attrs

    case Repo.insert(attrs |> StagingUpload.new_changeset()) do
      {:ok, staging_upload} ->
        # Store the file
        case Local.put(storage, storage_key, temp_path) do
          :ok ->
            # Enqueue extraction job if file was scanned clean
            if scan_status != :infected do
              enqueue_extraction(staging_upload)
            end
            {:ok, {:created, staging_upload}}
          {:error, reason} ->
            Logger.error("Failed to store file: #{inspect(reason)}")
            {:error, :storage_failed}
        end
      {:error, %Ecto.ConstraintError{constraint: "staging_uploads_source_hash_index"}} ->
        # Race condition: another process created the same staging upload
        existing = Repo.get_by!(StagingUpload, source_hash: source_hash)
        {:ok, {:existing, existing}}
      {:error, changeset} ->
        Logger.error("Failed to create staging upload: #{inspect(changeset.errors)}")
        {:error, :validation_failed}
    end
  end

  @doc """
  Gets staging upload by ID.
  """
  def get_staging_upload(staging_upload_id) do
    Repo.get(StagingUpload, staging_upload_id)
  end

  @doc """
  Lists staging uploads with optional filtering.
  """
  def list_staging_uploads(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)
    
    query = from s in StagingUpload,
            order_by: [desc: s.inserted_at],
            limit: ^limit

    query = if status, do: where(query, [s], s.status == ^status), else: query
    
    Repo.all(query)
  end

  # Private functions

  defp get_file_size(file_path) do
    case File.size(file_path) do
      size when is_integer(size) ->
        {:ok, size}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp perform_scan(file_path) do
    scan_result = AV.scan(file_path)
    {:ok, scan_result}
  end

  defp generate_storage_key(source_hash, content_type) do
    extension = get_extension_from_mime(content_type)
    Local.storage_key(source_hash, extension)
  end

  defp get_extension_from_mime(content_type) do
    case content_type do
      "application/pdf" -> ".pdf"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> ".docx"
      "text/plain" -> ".txt"
      _ -> ""
    end
  end

  defp enqueue_extraction(%StagingUpload{staging_upload_id: staging_upload_id}) do
    case Oban.insert(%Oban.Job{
      worker: Evhlegalchat.Ingest.ExtractWorker,
      args: %{"staging_upload_id" => staging_upload_id}
    }) do
      {:ok, _job} ->
        Logger.info("Enqueued extraction job for staging_upload_id: #{staging_upload_id}")
      {:error, reason} ->
        Logger.error("Failed to enqueue extraction job: #{inspect(reason)}")
    end
  end

  defp emit_telemetry(event, metadata, measurements \\ %{}) do
    :telemetry.execute([:evhlegalchat, :ingest, event], measurements, metadata)
  end
end
