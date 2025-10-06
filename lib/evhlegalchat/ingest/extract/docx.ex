defmodule Evhlegalchat.Ingest.Extract.DOCX do
  @moduledoc """
  DOCX text extraction using Pandoc and LibreOffice fallback.
  
  Handles Microsoft Word documents (.docx) with structured text output.
  """

  require Logger
  alias Evhlegalchat.Ingest.Extract.Port
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
  Extracts text and metadata from a DOCX file.
  
  Returns %ExtractResult{} struct with extracted content and metrics.
  """
  def extract(docx_path, temp_dir) do
    Logger.info("Starting DOCX extraction",
      file: docx_path,
      temp_dir: temp_dir
    )

    with :ok <- validate_file(docx_path),
         {:ok, tools} <- check_tools(),
         extract_method <- choose_extraction_method(tools),
         {:ok, text} <- extract_text(docx_path, temp_dir, extract_method),
         pages <- create_page_structure(text),
         {:ok, tools_with_versions} <- get_tool_versions(tools) do
      
      char_count = String.length(text)
      word_count = Metrics.word_count(text)
      
      Logger.info("DOCX extraction completed",
        char_count: char_count,
        word_count: word_count,
        method: extract_method
      )
      
      result = %__MODULE__{
        text: text,
        pages: pages,
        page_count: 1,
        char_count: char_count,
        word_count: word_count,
        ocr: false,
        ocr_confidence: nil,
        tools_used: tools_with_versions,
        previews_generated: false
      }

      {:ok, result}
    else
      {:error, :file_too_large} ->
        Logger.error("DOCX file exceeds size limit", file: docx_path)
        {:error, :file_too_large}
      
      {:error, {:tool_missing, tools}} ->
        Logger.error("Required DOCX tools missing", missing: tools)
        {:error, {:tool_missing, tools}}
      
      error ->
        Logger.error("DOCX extraction failed", error: error)
        {:error, error}
    end
  end

  # Private functions

  defp validate_file(docx_path) do
    case File.stat(docx_path) do
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

  defp check_tools do
    tools = %{}
    
    tools = if Port.command_available?("pandoc") do
      Map.put(tools, :pandoc, true)
    else
      tools
    end
    
    tools = if Port.command_available?("libreoffice") do
      Map.put(tools, :libreoffice, true)  
    else
      tools
    end
    
    # Must have at least one extraction tool
    if Map.size(tools) > 0 do
      {:ok, tools}
    else
      {:error, {:tool_missing, [:pandoc, :libreoffice]}}
    end
  end

  defp choose_extraction_method(tools) do
    cond do
      Map.has_key?(tools, :pandoc) -> :pandoc
      Map.has_key?(tools, :libreoffice) -> :libreoffice
      true -> :none
    end
  end

  defp extract_text(docx_path, temp_dir, method) do
    case method do
      :pandoc ->
        extract_with_pandoc(docx_path)
      
      :libreoffice ->
        extract_with_libreoffice(docx_path, temp_dir)
      
      :none ->
        {:error, :no_extraction_tools}
    end
  end

  defp extract_with_pandoc(docx_path) do
    timeout = Application.get_env(:evhlegalchat, Evhlegalchat.Ingest.Extract, [])
             |> Keyword.get(:timeout_per_file, 300_000)
    
    Logger.debug("Using Pandoc via docx_path", path: docx_path)
    
    case Port.run("pandoc", 
      ["-f", "docx", "-t", "plain", "--wrap=none", "--columns=120", docx_path, "--no-highlight"],
      timeout: timeout
    ) do
      {:ok, text} ->
        # Clean up Pandoc output
        cleaned_text = text
        |> String.replace(~r/\n{3,}/, "\n\n")  # Normalize multiple newlines
        |> String.trim()
        
        {:ok, cleaned_text}
      
      {:error, {:exit_status, status, stderr}} ->
        Logger.warning("Pandoc extraction failed",
          exit_status: status,
          stderr: String.slice(stderr, 0, 200)
        )
        {:error, {:tool_error, :pandoc, status}}
      
      error ->
        Logger.error("Pandoc unexpected error", error: error)
        {:error, error}
    end
  end

  defp extract_with_libreoffice(docx_path, temp_dir) do
    output_dir = Path.join(temp_dir, "docx_output")
    File.mkdir_p!(output_dir)
    
    timeout = Application.get_env(:evhlegalchat, Evhlegalchat.Ingest.Extract, [])
             |> Keyword.get(:timeout_per_file, 300_000)
    
    Logger.debug("Using LibreOffice for DOCX extraction", 
      docx_path: docx_path, 
      output_dir: output_dir
    )
    
    # LibreOffice conversion command
    case Port.run("libreoffice",
      ["--headless", "--convert-to", "txt:Text", "--outdir", output_dir, docx_path],
      timeout: timeout
    ) do
      {:ok, _output} ->
        # Find the generated TXT file
        output_files = File.ls!(output_dir) 
                     |> Enum.filter(&String.ends_with?(&1, ".txt"))
        
        if output_files != [] do
          txt_file_path = Path.join(output_dir, hd(output_files))
          
          case File.read(txt_file_path) do
            {:ok, text} ->
              # LibreOffice sometimes converts to Windows-style encoding
              # Try to clean up and ensure UTF-8
              cleaned_text = text
              |> normalize_encoding()
              |> String.replace(~r/\r\n|\r/, "\n")  # Normalize line endings
              |> String.replace(~r/\n{3,}/, "\n\n")  # Normalize multiple newlines
              |> String.trim()
              
              {:ok, cleaned_text}
            {:error, reason} ->
              Logger.error("Failed to read LibreOffice output file", file: txt_file_path, reason: reason)
              {:error, :file_read_error}
          end
        else
          Logger.error("No TXT file generated by LibreOffice", output_files: output_files)
          {:error, :no_output_file}
        end
      
      {:error, {:exit_status, status, stderr}} ->
        Logger.error("LibreOffice conversion failed", status: status, stderr: String.slice(stderr, 0, 200))
        {:error, {:tool_error, :libreoffice, status}}
      
      error ->
        Logger.error("LibreOffice unexpected error", error: error)
        {:error, error}
    end
  end

  defp normalize_encoding(text) do
    case :unicode.characters_to_binary(text, :utf8, :utf8) do
      {:ok, utf8_text, _rest} ->
        utf8_text
      {:error, _utf8_text, _rest} ->
        # Try ISO-8859-1 -> UTF-8 conversion
        case :unicode.characters_to_binary(text, :latin1, :utf8) do
          utf8_text when is_binary(utf8_text) ->
            utf8_text
          _ ->
            # Fallback: remove invalid characters
            String.replace(text, ~r/[^\x00-\x7F]/, "_")
        end
    end
  end

  defp create_page_structure(text) do
    # DOCX doesn't have natural page breaks, so create a single "page"
    [
      %{
        page: 1,
        text: text,
        char_count: String.length(text)
      }
    ]
  end

  defp get_tool_versions(tools) do
    versions = Map.new(tools, fn {tool, _available} ->
      version = Port.get_version(tool, ["--version", "-V", "-v"]) || "unknown"
      {tool, version}
    end)
    
    {:ok, versions}
  end
end
