defmodule Evhlegalchat.Nda.PdfParser do
  @moduledoc """
  PDF text extraction utility using pdftotext command-line tool.
  """

  require Logger

  @doc """
  Extracts text from a PDF file using pdftotext.

  ## Parameters
  - `file_path`: Path to the PDF file

  ## Returns
  - `{:ok, text}` on success
  - `{:error, reason}` on failure
  """
  def extract_text(file_path) when is_binary(file_path) do
    if File.exists?(file_path) do
      case check_pdftotext_available() do
        :ok -> do_extract_text(file_path)
        error -> error
      end
    else
      {:error, "File does not exist: #{file_path}"}
    end
  end

  def extract_text(_), do: {:error, "Invalid file path"}

  defp do_extract_text(file_path) do
    # Use pdftotext to extract text to stdout
    case System.cmd("pdftotext", [file_path, "-"], stderr_to_stdout: true) do
      {text, 0} ->
        cleaned_text = clean_extracted_text(text)
        {:ok, cleaned_text}

      {error_output, exit_code} ->
        Logger.error("pdftotext failed with exit code #{exit_code}: #{error_output}")
        {:error, "PDF text extraction failed: #{error_output}"}
    end
  rescue
    error ->
      Logger.error("Error running pdftotext: #{inspect(error)}")
      {:error, "Failed to run pdftotext: #{Exception.message(error)}"}
  end

  defp check_pdftotext_available do
    try do
      case System.cmd("pdftotext", ["-h"], stderr_to_stdout: true) do
        {_output, _exit_code} ->
          :ok
      end
    rescue
      _error ->
        Logger.warning("pdftotext not available, will skip PDF text extraction")
        {:error, "pdftotext command not found. For PDF support, please install poppler-utils."}
    end
  end

  defp clean_extracted_text(text) do
    text
    |> String.trim()
    # Replace multiple whitespace with single space
    |> String.replace(~r/\s+/, " ")
    # Preserve paragraph breaks
    |> String.replace(~r/\n\s*\n/, "\n\n")
  end

  @doc """
  Extracts text from uploaded file entry during Phoenix LiveView upload process.

  ## Parameters
  - `entry`: Phoenix LiveView upload entry
  - `temp_path`: Temporary file path from upload

  ## Returns
  - `{:ok, text}` on success
  - `{:error, reason}` on failure
  """
  def extract_from_upload(entry, temp_path) do
    case Path.extname(entry.client_name) |> String.downcase() do
      ".pdf" -> extract_text(temp_path)
      ".txt" -> extract_text_file(temp_path)
      ext -> {:error, "Unsupported file type: #{ext}"}
    end
  end

  defp extract_text_file(file_path) do
    case File.read(file_path) do
      {:ok, content} -> {:ok, String.trim(content)}
      error -> error
    end
  end
end
