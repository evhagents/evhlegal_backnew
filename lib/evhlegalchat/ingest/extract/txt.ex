defmodule Evhlegalchat.Ingest.Extract.TXT do
  @moduledoc """
  Plain text file normalization and extraction.
  
  Handles encoding detection, normalization, and cleanup of plain text files.
  """

  require Logger
  alias Evhlegalchat.Ingest.Extract.Metrics

  defstruct [
    :text,
    :pages,
    :page_count,
    :char_count,
    :word_count,
    :ocr,
    :ocr_confidence,
    :tools_used,
    :previews_generated
  ]

  @doc """
  Extracts and normalizes text from a TXT file.
  
  Returns %ExtractResult{} struct with normalized content and metrics.
  """
  def extract(txt_path, _temp_dir) do
    Logger.info("Starting TXT extraction",
      file: txt_path
    )

    with :ok <- validate_file(txt_path),
         {:ok, raw_content} <- SafeFile.read(txt_path),
         {:ok, normalized_text} <- normalize_text(raw_content),
         pages <- create_page_structure(normalized_text) do
      
      char_count = String.length(normalized_text)
      word_count = Metrics.word_count(normalized_text)
      
      Logger.info("TXT extraction completed",
        char_count: char_count,
        word_count: word_count
      )
      
      result = %__MODULE__{
        text: normalized_text,
        pages: pages,
        page_count: 1,
        char_count: char_count,
        word_count: word_count,
        ocr: false,
        ocr_confidence: nil,
        tools_used: %{"native" => "elixir"},
        previews_generated: false
      }

      {:ok, result}
    else
      {:error, :file_too_large} ->
        Logger.error("TXT file exceeds size limit", file: txt_path)
        {:error, :file_too_large}
      
      error ->
        Logger.error("TXT extraction failed", error: error)
        {:error, error}
    end
  end

  # Private functions

  defp validate_file(txt_path) do
    case File.stat(txt_path) do
      {:ok, %{size: size}} ->
        max_size = Application.get_env(:evhlegalchat, Evhlegalchat.Ingest.Extract, [])
                  |> Keyword.get(:max_byte_size, 100_000_000)
        
        if size <= max_size do
          :ok
        else
          {:error, :file_too_large}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp safe_file_read(txt_path) do
    try do
      case File.read(txt_path) do
        {:ok, content} ->
          {:ok, content}
        {:error, reason} ->
          Logger.error("Failed to read TXT file", file: txt_path, reason: reason)
          {:error, {:file_read_error, reason}}
      end
    rescue
      error ->
        Logger.error("Exception reading TXT file", error: error)
        {:error, {:file_read_exception, error}}
    end
  end

  defp normalize_text(raw_content) do
    try do
      # Step 1: Detect encoding and convert to UTF-8
      utf8_content = detect_and_convert_encoding(raw_content)
      
      # Step 2: Remove null bytes and invalid control characters
      clean_content = remove_invalid_characters(utf8_content)
      
      # Step 3: Normalize line endings
      normalized_lines = normalize_line_endings(clean_content)
      
      # Step 4: Trim excessive whitespace
      trimmed_content = trim_excessive_whitespace(normalized_lines)
      
      # Step 5: Final validation
      case validate_content(trimmed_content) do
        :ok ->
          {:ok, trimmed_content}
        {:error, reason} ->
          Logger.warning("Content validation failed", reason: reason)
          {:ok, trimmed_content}  # Return anyway, just warn
      end
    rescue
      error ->
        Logger.error("Text normalization failed", error: error)
        {:error, {:normalization_error, error}}
    end
  end

  defp detect_and_convert_encoding(raw_content) do
    case :unicode.characters_to_binary(raw_content, :utf8, :utf8) do
      {:ok, utf8_content, _rest} ->
        utf8_content
      
      {:error, _utf8_content, _rest} ->
        # Try common encodings
        detect_encoding_fallback(raw_content)
    end
  end

  defp detect_encoding_fallback(raw_content) do
    # Try Windows-1252 (common on Windows)
    case :unicode.characters_to_binary(raw_content, :cp1252, :utf8) do
      utf8_content when is_binary(utf8_content) ->
        utf8_content
      _ ->
        # Try ISO-8859-1 (Latin-1)
        case :unicode.characters_to_binary(raw_content, :latin1, :utf8) do
          utf8_content when is_binary(utf8_content) ->
            utf8_content
          _ ->
            # Last resort: replace invalid chars
            Logger.warning("Unable to detect encoding, removing invalid characters")
            String.codepoints(raw_content)
            |> Enum.map(fn codepoint ->
              if String.valid?(codepoint), do: codepoint, else: "_"
            end)
            |> Enum.join("")
        end
    end
  end

  defp remove_invalid_characters(content) do
    # Allow printable characters, newlines, carriage returns, and tabs
    valid_chars = ~r/[^\x20-\x7E\n\r\t\u00A0-\uFFFF]/
    String.replace(content, valid_chars, "")
  end

  defp normalize_line_endings(content) do
    content
    |> String.replace(~r/\r\n/, "\n")  # CRLF -> LF
    |> String.replace(~r/\r(?![^\n])/, "\n")  # CR -> LF (except CRLF)
  end

  defp trim_excessive_whitespace(content) do
    content
    |> String.replace(~r/[ \t]+/, " ")  # Multiple spaces/tabs -> single space
    |> String.replace(~r/\n[ \t]+/, "\n")  # Leading whitespace after newline
    |> String.replace(~r/[ \t]+\n/, "\n")  # Trailing blacks line
    |> String.replace(~r/\n{3,}/, "\n\n")  # Multiple newlines -> double newline
    |> String.trim()
  end

  defp validate_content(content) do
    cond do
      String.length(content) == 0 ->
        {:error, :empty_content}
      
      String.length(content) > 50_000_000 ->  # 50MB limit on content
        {:error, :content_too_large}
      
      contains_only_whitespace?(content) ->
        {:error, :whitespace_only}
      
      true ->
        :ok
    end
  end

  defp contains_only_whitespace?(content) do
    content
    |> String.replace(~r/\s/, "")
    |> String.length() == 0
  end

  defp create_page_structure(text) do
    # Plain text files typically don't have page breaks
    # Create a single "page" structure
    [
      %{
        page: 1,
        text: text,
        char_count: String.length(text)
      }
    ]
  end
end
