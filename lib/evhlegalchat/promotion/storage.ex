defmodule Evhlegalchat.Promotion.Storage do
  @moduledoc """
  File promotion utilities for moving artifacts from staging to canonical storage.
  
  Handles atomic file operations with verification and rollback support.
  """

  require Logger
  alias Evhlegalchat.Storage.Local

  @doc """
  Promotes artifacts from staging to canonical agreement storage.
  
  Returns {:ok, promoted_keys} or {:error, reason}.
  """
  def promote!(staging_upload, agreement_id, artifacts) do
    Logger.info("Starting artifact promotion", 
      staging_upload_id: staging_upload.staging_upload_id,
      agreement_id: agreement_id
    )

    with {:ok, original_key} <- promote_original_file(staging_upload, agreement_id),
         {:ok, text_keys} <- promote_text_artifacts(agreement_id, artifacts),
         {:ok, metrics_key} <- promote_metrics(agreement_id, artifacts),
         {:ok, preview_keys} <- promote_previews(agreement_id, artifacts) do
      
      promoted_keys = %{
        original: original_key,
        text_concat: text_keys.concatenated,
        pages_jsonl: text_keys.pages,
        metrics: metrics_key,
        previews: preview_keys
      }
      
      Logger.info("Artifact promotion completed",
        agreement_id: agreement_id,
        promoted_count: map_size(promoted_keys)
      )
      
      {:ok, promoted_keys}
    end
  end

  @doc """
  Builds canonical storage keys for an agreement.
  """
  def build_canonical_keys(agreement_id) do
    %{
      original: "agreements/#{agreement_id}/original/",
      text: "agreements/#{agreement_id}/text/",
      metrics: "agreements/#{agreement_id}/metrics.json",
      previews: "agreements/#{agreement_id}/previews/"
    }
  end

  # Private functions

  defp promote_original_file(staging_upload, agreement_id) do
    source_key = staging_upload.storage_key
    source_hash = staging_upload.source_hash
    source_filename = staging_upload.source_file_name
    
    # Extract file extension
    extension = Path.extname(source_filename)
    
    # Build canonical key
    canonical_key = "agreements/#{agreement_id}/original/#{source_hash}#{extension}"
    
    # Copy file atomically
    copy_file_atomically(source_key, canonical_key)
  end

  defp promote_text_artifacts(agreement_id, artifacts) do
    text_keys = %{
      concatenated: "agreements/#{agreement_id}/text/concatenated.txt",
      pages: "agreements/#{agreement_id}/text/pages.jsonl"
    }
    
    with {:ok, _} <- copy_file_atomically(artifacts["text_concat"], text_keys.concatenated),
         {:ok, _} <- copy_file_atomically(artifacts["pages_jsonl"], text_keys.pages) do
      {:ok, text_keys}
    end
  end

  defp promote_metrics(agreement_id, artifacts) do
    canonical_key = "agreements/#{agreement_id}/metrics.json"
    
    case copy_file_atomically(artifacts["metrics"], canonical_key) do
      {:ok, _} -> {:ok, canonical_key}
      error -> error
    end
  end

  defp promote_previews(agreement_id, artifacts) do
    previews_prefix = artifacts["previews_prefix"]
    
    if previews_prefix do
      # List all preview files in staging
      staging_storage = Local.new()
      
      case Local.list_files(staging_storage, previews_prefix) do
        {:ok, preview_files} ->
          preview_keys = Enum.map(preview_files, fn preview_file ->
            filename = Path.basename(preview_file)
            canonical_key = "agreements/#{agreement_id}/previews/#{filename}"
            
            case copy_file_atomically(preview_file, canonical_key) do
              {:ok, _} -> canonical_key
              {:error, reason} -> 
                Logger.warning("Failed to promote preview file", 
                  file: preview_file, 
                  reason: reason
                )
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          
          {:ok, preview_keys}
        {:error, reason} ->
          Logger.warning("Failed to list preview files", reason: reason)
          {:ok, []}
      end
    else
      {:ok, []}
    end
  end

  defp copy_file_atomically(source_key, target_key) do
    storage = Local.new()
    
    # Create temporary file for atomic write
    temp_key = "#{target_key}.tmp.#{System.unique_integer()}"
    
    try do
      with {:ok, source_path} <- Local.get(storage, source_key),
           {:ok, _} <- Local.put(storage, temp_key, source_path),
           {:ok, _} <- verify_file_integrity(storage, source_key, temp_key),
           :ok <- Local.move(storage, temp_key, target_key) do
        {:ok, target_key}
      else
        {:error, reason} ->
          # Clean up temp file on failure
          Local.delete(storage, temp_key)
          {:error, reason}
      end
    rescue
      error ->
        # Clean up temp file on exception
        Local.delete(storage, temp_key)
        {:error, error}
    end
  end

  defp verify_file_integrity(storage, source_key, temp_key) do
    with {:ok, source_path} <- Local.get(storage, source_key),
         {:ok, temp_path} <- Local.get(storage, temp_key) do
      
      # Compare file sizes
      source_size = File.stat!(source_path).size
      temp_size = File.stat!(temp_path).size
      
      if source_size == temp_size do
        {:ok, temp_key}
      else
        {:error, {:size_mismatch, source_size, temp_size}}
      end
    end
  end
end
