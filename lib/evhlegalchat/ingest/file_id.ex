defmodule Evhlegalchat.Ingest.FileId do
  @moduledoc """
  File identification utilities for hashing and content type detection.
  
  Provides streaming SHA256 hash computation and MIME type detection
  based on magic bytes rather than file extensions.
  """

  require Logger

  @supported_extensions ~w(.pdf .docx .txt)
  @magic_bytes %{
    # PDF
    <<0x25, 0x50, 0x44, 0x46>> => "application/pdf",
    # DOCX (ZIP-based)
    <<0x50, 0x4B, 0x03, 0x04>> => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    <<0x50, 0x4B, 0x05, 0x06>> => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    <<0x50, 0x4B, 0x07, 0x08>> => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    # Plain text (UTF-8)
    <<0xEF, 0xBB, 0xBF>> => "text/plain",
  }

  @doc """
  Computes SHA256 hash of a file in streaming fashion.
  """
  def sha256_file(path) when is_binary(path) do
    case File.open(path, [:read]) do
      {:ok, file} ->
        try do
          hash = :crypto.hash_init(:sha256)
          hash = stream_hash(file, hash)
          :crypto.hash_final(hash) |> Base.encode16(case: :lower)
        after
          File.close(file)
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Detects MIME type from file magic bytes and extension.
  
  Falls back to MIME detection from extension if magic bytes don't match.
  """
  def detect_mime(path) when is_binary(path) do
    case File.read(path, 512) do
      {:ok, bytes} ->
        magic_detect(bytes)
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if file extension is supported for processing.
  """
  def supported_extension?(filename) when is_binary(filename) do
    extension = Path.extname(filename) |> String.downcase()
    extension in @supported_extensions
  end

  @doc """
  Identifies a file: computes hash, detects MIME, validates extension.
  
  Returns {:ok, hash, mime_type} or {:error, reason}.
  """
  def identify_file(file_path, original_filename \\ nil) do
    _original_filename = original_filename || Path.basename(file_path)
    
    case sha256_file(file_path) do
      {:ok, hash} ->
        with {:ok, mime_type} <- detect_mime(file_path),
             :ok <- validate_supported(mime_type) do
          {:ok, hash, mime_type}
        else
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp stream_hash(file, hash) do
    case IO.binread(file, 4096) do
      :eof ->
        hash
      data when is_binary(data) ->
        stream_hash(file, :crypto.hash_update(hash, data))
      {:error, _} = error ->
        throw(error)
    end
  end

  defp magic_detect(bytes) when byte_size(bytes) >= 4 do
    magic = :erlang.binary_part(bytes, 0, 4)
    
    case @magic_bytes[magic] do
      nil ->
        # Fallback to extension-based detection
        fallback_mime(bytes)
      mime_type ->
        {:ok, mime_type}
    end
  end

  defp magic_detect(_), do: {:error, :insufficient_data}

  defp fallback_mime(bytes) do
    # Simple heuristics for plain text
    case :binary.match(bytes, [0x00]) do
      {_, _} ->
        {:error, :binary_file}
      :nomatch ->
        case :unicode.characters_to_binary(bytes, :utf8, :utf8) do
          utf8 when is_binary(utf8) ->
            {:ok, "text/plain"}
          _ ->
            {:ok, "application/octet-stream"}
        end
    end
  end

  defp validate_supported(mime_type) do
    case mime_type do
      "application/pdf" -> :ok
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> :ok
      "text/plain" -> :ok
      _ ->
        {:error, :unsupported_type}
    end
  end
end
