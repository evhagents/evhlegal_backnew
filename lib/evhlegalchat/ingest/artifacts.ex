defmodule Evhlegalchat.Ingest.Artifacts do
  @moduledoc """
  Helper module for managing extraction artifacts in secure storage.
  
  Provides deterministic storage key generation and artifact lifecycle management.
  """

  require Logger
  alias Evhlegalchat.Storage.Local

  @artifact_types %{
    text_concat: "text/concatenated.txt",
    pages_jsonl: "text/pages.jsonl", 
    metrics: "metrics.json",
    previews: "previews/"
  }

  @doc """
  Builds a deterministic storage key for an artifact.
  
  ## Examples
  
      iex> build_artifact_key(42, :text_concat)
      "staging/42/text/concatenated.txt"
      
      iex> build_artifact_key(42, :previews)
      "staging/42/previews/"
  """
  def build_artifact_key(staging_upload_id, artifact_type) when is_integer(staging_upload_id) do
    case @artifact_types[artifact_type] do
      nil ->
        raise ArgumentError, "Unknown artifact type: #{artifact_type}"
      path ->
        "staging/#{staging_upload_id}/#{path}"
    end
  end

  @doc """
  Builds a preview image key for a specific page.
  """
  def build_preview_key(staging_upload_id, page_number) when is_integer(staging_upload_id) and is_integer(page_number) do
    "staging/#{staging_upload_id}/previews/page-#{String.pad_leading(to_string(page_number), 4, "0")}.png"
  end

  @doc """
  Uploads an artifact to storage by type.
  
  Returns {:ok, storage_key} or {:error, reason}.
  """
  def upload_artifact(storage_key, local_path, _opts \\ []) do
    storage = Local.new()
    
    case Local.put(storage, storage_key, local_path) do
      :ok ->
        {:ok, storage_key}
      {:error, reason} ->
        Logger.error("Failed to upload artifact #{storage_key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Downloads an artifact from storage to a local path.
  
  Returns {:ok, local_path} or {:error, reason}.
  """
  def download_artifact(storage_key, local_target_path) do
    storage = Local.new()
    
    case Local.get(storage, storage_key) do
      {:ok, file_path} ->
        # Copy to target location if different
        if file_path != local_target_path do
          case File.copy(file_path, local_target_path) do
            {:ok, _} -> {:ok, local_target_path}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, file_path}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if an artifact exists in storage storage.
  """
  def artifact_exists?(storage_key) do
    storage = Local.new()
    
    case Local.head(storage, storage_key) do
      {:ok, _meta} -> true
      {:error, :not_found} -> false
      {:error, _reason} -> false
    end
  end

  @doc """
  Downloads a JSON artifact and parses it.
  
  Returns {:ok, parsed_data} or {:error, reason}.
  """
  def download_and_parse_json(storage_key) do
    temp_path = Path.join(System.tmp_dir!(), "json_#{System.unique_integer()}.json")
    
    try do
      case download_artifact(storage_key, temp_path) do
        {:ok, file_path} ->
          case File.read(file_path) do
            {:ok, json_string} ->
              case Jason.decode(json_string) do
                {:ok, data} -> {:ok, data}
                {:error, reason} -> {:error, {:json_decode, reason}}
              end
            {:error, reason} ->
              {:error, reason}
          end
        {:error, reason} ->
          {:error, reason}
      end
    after
      if File.exists?(temp_path) do
        File.rm!(temp_path)
      end
    end
  end

  @doc """
  Validates that required artifacts exist and are properly formed.
  
  Checks for:
  - Text concatenated file existence
  - Metrics file existence and validity
  - Pages JSONL file existence (optional)
  
  Returns true if all required artifacts are valid.
  """
  def validate_artifacts(_staging_upload_id, artifact_keys) do
    required_files = [
      {"text_concat", artifact_keys["text_concat"]},
      {"metrics", artifact_keys["metrics"]}
    ]

    # Check all required files exist
    all_exist = Enum.all?(required_files, fn {_name, storage_key} ->
      artifact_exists?(storage_key)
    end)

    if not all_exist do
      false
    else
      # Validate metrics.json structure
      case download_and_parse_json(artifact_keys["metrics"]) do
        {:ok, metrics} ->
          valid_metrics?(metrics)
        _ ->
          false
      end
    end
  end

  @doc """
  Checks if metrics data is valid (has required fields).
  """
  def valid_metrics?(%{"page_count" => page_count, "char_count" => char_count}) 
    when is_number(page_count) and page_count > 0 and 
         is_number(char_count) and char_count > 0 do
    true
  end
  def valid_metrics?(_), do:
    false

  @doc """
  Builds artifact keys map for a staging upload ID.
  """
  def build_artifact_keys_map(staging_upload_id) when is_integer(staging_upload_id) do
    %{
      "text_concat" => build_artifact_key(staging_upload_id, :text_concat),
      "pages_jsonl" => build_artifact_key(staging_upload_id, :pages_jsonl),
      "metrics" => build_artifact_key(staging_upload_id, :metrics),
      "previews_prefix" => build_artifact_key(staging_upload_id, :previews)
    }
  end

  @doc """
  Removes nil values from artifact keys map.
  
  Useful before storing in database metadata.
  """
  def clean_artifact_keys(artifact_keys_map) when is_map(artifact_keys_map) do
    artifact_keys_map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into(%{})
  end
end
