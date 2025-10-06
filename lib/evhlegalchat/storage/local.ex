defmodule Evhlegalchat.Storage.Local do
  @moduledoc """
  Local filesystem storage adapter.
  
  Stores files in a configured root directory with safe atomic operations.
  """

  @behaviour Evhlegalchat.Storage
  require Logger

  defstruct [:root]

  @doc """
  Creates a new Local storage adapter.
  """
  def new(root \\ default_root()) do
    %__MODULE__{root: Path.expand(root)}
  end

  @doc """
  Stores a file atomically with fsync for durability.
  """
  def put(%__MODULE__{root: root}, key, source_path) do
    target_path = Path.join(root, key)
    target_dir = Path.dirname(target_path)
    temp_path = "#{target_path}.tmp.#{:rand.uniform(1_000_000)}"

    with :ok <- File.mkdir_p(target_dir),
         :ok <- File.copy(source_path, temp_path),
         :ok <- ensure_file_synced(temp_path),
         :ok <- File.rename(temp_path, target_path),
         :ok <- ensure_file_synced(target_path) do
      :ok
    else
      {:error, reason} = error ->
        File.rm_rf(temp_path)
        Logger.warning("Failed to store file at #{target_path}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Retrieves the path to a stored file.
  """
  def get(%__MODULE__{root: root}, key) do
    file_path = Path.join(root, key)

    if File.exists?(file_path) do
      {:ok, file_path}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Gets file metadata (size, modification time).
  """
  def head(%__MODULE__{root: root}, key) do
    file_path = Path.join(root, key)

    case File.stat(file_path) do
      {:ok, stat} ->
        {:ok, %{size: stat.size, mtime: stat.mtime}}
      {:error, :enoent} ->
        {:error, :not_found}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Deletes a stored file.
  """
  def delete(%__MODULE__{root: root}, key) do
    file_path = Path.join(root, key)

    case File.rm(file_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates a deterministic storage key from source hash and extension.
  """
  def storage_key(source_hash, extension, date \\ Date.utc_today()) do
    encoded_hash = Base.encode32(source_hash, case: :lower, padding: false)
    formatted_date = Date.to_iso8601(date) |> String.replace("-", "/")
    "#{formatted_date}/#{encoded_hash}#{extension}"
  end

  # Private functions

  defp default_root do
    Application.get_env(:evhlegalchat, __MODULE__, [])
    |> Keyword.get(:root, "priv/storage")
  end

  defp ensure_file_synced(path) do
    case :file.sync(path) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
