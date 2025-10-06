defmodule Evhlegalchat.Ingest.Extract.PDF do
  @moduledoc """
  PDF text extraction using pdftotext and optional OCR with Tesseract.
  
  Handles both searchable PDFs and image-based PDFs requiring OCR.
  Generates structured page output and optional preview images.
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

  @ocr_threshold_chars 100
  @ocr_threshold_nonprintable 0.3
  @max_preview_pages 10

  @doc """
  Extracts text and metadata from a PDF file.
  
  Returns %ExtractResult{} struct with extracted content and metrics.
  """
  def extract(pdf_path, temp_dir) do
    Logger.info("Starting PDF extraction", 
      file: pdf_path, 
      temp_dir: temp_dir
    )

    with :ok <- validate_file(pdf_path),
         {:ok, tools} <- check_tools(),
         {:ok, page_count} <- get_page_count(pdf_path),
         :ok <- validate_page_count(page_count),
         result <- extract_text(pdf_path, temp_dir, tools, page_count) do
      
      Logger.info("PDF extraction completed",
        page_count: result.page_count,
        char_count: result.char_count,
        ocr: result.ocr,
        ocr_confidence: result.ocr_confidence
      )
      
      {:ok, result}
    else
      {:error, :file_too_large} ->
        Logger.error("PDF file exceeds size limit", file: pdf_path)
        {:error, :file_too_large}
        
      {:error, :tool_missing, tools} ->
        Logger.error("Required PDF tools missing", missing: tools)
        {:error, {:tool_missing, tools}}
        
      {:error, :too_many_pages, page_count} ->
        Logger.error("PDF exceeds page limit", 
          page_count: page_count, 
          limit: Application.get_env(:evhlegalchat, Evhlegalchat.Ingest.Extract, []) |> Keyword.get(:max_pages, 1000)
        )
        {:error, {:too_many_pages, page_count}}
        
      error ->
        Logger.error("PDF extraction failed", error: error)
        {:error, error}
    end
  end

  # Private functions

  defp validate_file(pdf_path) do
    case File.stat(pdf_path) do
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
    
    tools = if Port.command_available?("pdftotext") do
      Map.put(tools, :pdftotext, true)
    else
      tools
    end
    
    tools = if Port.command_available?("tesseract") do
      Map.put(tools, :tesseract, true)
    else
      tools
    end
    
    tools = if Port.command_available?("pdftoppm") do
      Map.put(tools, :pdftoppm, true)
    else
      tools
    end
    
    if Map.has_key?(tools, :pdftotext) do
      {:ok, tools}
    else
      {:error, {:tool_missing, [:pdftotext]}}
    end
  end

  defp get_page_count(pdf_path) do
    with {:ok, output} <- Port.run("pdfinfo", ["-1", pdf_path], timeout: 10_000) do
      case Regex.run(~r/Pages:\s*(\d+)/, output) do
        [_, pages_str] ->
          {:ok, String.to_integer(pages_str)}
        _ ->
          # Fallback: try pdfinfo with different flags
          case Port.run("pdfinfo", [pdf_path], timeout: 10_000) do
            {:ok, alt_output} ->
              case Regex.run(~r/Pages:\s*(\d+)/, alt_output) do
                [_, pages_str] -> {:ok, String.to_integer(pages_str)}
                _ -> {:ok, 1}  # Assume single page if can't determine
              end
            _ ->
              {:ok, 1}  # Fallback
          end
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_page_count(page_count) do
    max_pages = Application.get_env(:evhlegalchat, Evhlegalchat.Ingest.Extract, [])
               |> Keyword.get(:max_pages, 1000)
    
    if page_count <= max_pages do
      :ok
    else
      {:error, {:too_many_pages, page_count}}
    end
  end

  defp extract_text(pdf_path, temp_dir, tools, page_count) do
    # Step 1: Try regular pdftotext first
    case extract_with_pdftotext(pdf_path) do
      {:ok, text, pages} when byte_size(text) > 0 ->
        assess_and_maybe_ocr(pdf_path, temp_dir, tools, text, pages, page_count)
      
      _ ->
        # Empty or failed extraction, go straight to OCR
        Logger.warning("PDfToText extracted no text, engaging OCR")
        extract_with_ocr(pdf_path, temp_dir, tools, page_count)
    end
  end

  defp extract_with_pdftotext(pdf_path) do
    timeout = Application.get_env(:evhlegalchat, Evhlegalchat.Ingest.Extract, [])
             |> Keyword.get(:timeout_per_file, 300_000)
    
    case Port.run("pdftotext", ["-layout", "-enc", "UTF-8", pdf_path, "-"], timeout: timeout) do
      {:ok, text} ->
        pages = create_page_structure(text)
        {:ok, text, pages}
      error ->
        Logger.warning("PDfToText extraction failed", error: error)
        error
    end
  end

  defp create_page_structure(text) do
    # Split on form-feed characters to create pages
    page_texts = String.split(text, "\f", trim: true)
    
    Enum.with_index(page_texts, 1)
    |> Enum.map(fn {page_text, page_num} ->
      %{
        page: page_num,
        text: page_text,
        char_count: String.length(page_text)
      }
    end)
  end

  defp assess_and_maybe_ocr(pdf_path, temp_dir, tools, pdftotext_text, pages, page_count) do
    char_count = String.length(pdftotext_text)
    avg_chars_per_page = div(char_count, page_count)
    
    # OCR heuristics
    needs_ocr = needs_ocr?(pdftotext_text, avg_chars_per_page)
    
    if needs_ocr and Map.has_key?(tools, :tesseract) do
      Logger.info("Engaging OCR based on quality assessment")
      ocr_result = extract_with_ocr(pdf_path, temp_dir, tools, page_count)
      
      case ocr_result do
        {:ok, struct} ->
          # Merge OCR result with better text if available
          final_text = if String.length(struct.text) > char_count do
            struct.text
          else
            pdftotext_text
          end
          
          %__MODULE__{
            text: final_text,
            pages: struct.pages,
            page_count: page_count,
            char_count: String.length(final_text),
            word_count: Metrics.word_count(final_text),
            ocr: true,
            ocr_confidence: struct.ocr_confidence,
            tools_used: struct.tools_used,
            previews_generated: struct.previews_generated
          }
        
        _ ->
          # OCR failed, use pdftotext result
          build_result(pdftotext_text, pages, page_count, false, nil, tools)
      end
    else
      # No OCR needed, use pdftotext result
      build_result(pdftotext_text, pages, page_count, false, nil, tools)
    end
  end

  defp needs_ocr?(text, avg_chars_per_page) do
    cond do
      avg_chars_per_page < @ocr_threshold_chars -> true
      calculate_nonprintable_ratio(text) > @ocr_threshold_nonprintable -> true  
      String.length(text) < 100 -> true
      true -> false
    end
  end

  defp calculate_nonprintable_ratio(text) do
    total_chars = String.length(text)
    
    nonprintable_count = text
    |> String.graphemes()
    |> Enum.count(fn char ->
      not Regex.match?(~r/[\x20-\x7E\n\r\t]/, char)
    end)
    
    if total_chars > 0 do
      nonprintable_count / total_chars
    else
      1.0
    end
  end

  defp extract_with_ocr(pdf_path, temp_dir, tools, page_count) do
    with {:ok, previews_generated} <- generate_previews(pdf_path, temp_dir, tools, page_count),
         {:ok, text, ocr_confidence} <- extract_text_with_tesseract(temp_dir) do
      
      pages = create_page_structure(text)
      
      {:ok, build_result(text, pages, page_count, true, ocr_confidence, 
        Map.put(tools, :previews, previews_generated))}
    else
      {:error, :preview_failure} ->
        # Fallback to text-only OCR
        with {:ok, text, ocr_confidence} <- ocr_text_only(pdf_path, temp_dir) do
          pages = create_page_structure(text)
          
          {:ok, build_result(text, pages, page_count, true, ocr_confidence, 
            Map.put(tools, :previews, false))}
        end
      
      error ->
        Logger.error("OCR extraction failed", error: error)
        {:error, error}
    end
  end

  defp generate_previews(pdf_path, temp_dir, tools, page_count) do
    if Map.has_key?(tools, :pdftoppm) and page_count <= @max_preview_pages do
      preview_dir = Path.join(temp_dir, "previews")
      File.mkdir_p!(preview_dir)
      
      preview_pages = min(page_count, @max_preview_pages)
      
      case Port.run("pdftoppm", 
        ["-png", "-r", "150", "-f", "1", "-l", to_string(preview_pages), pdf_path], 
        timeout: 60_000,
        cwd: preview_dir
      ) do
        {:ok, _} ->
          {:ok, true}
        error ->
          Logger.warning("Preview generation failed", error: error)
          {:error, :preview_failure}
      end
    else
      {:ok, false}
    end
  end

  defp extract_text_with_tesseract(temp_dir) do
    preview_dir = Path.join(temp_dir, "previews")
    
    if File.exists?(preview_dir) do
      pages_dir = Path.join(preview_dir, "pages")
      File.mkdir_p!(pages_dir)
      
      # Convert preview images back to individual pages
      File.ls!(preview_dir)
      |> Enum.filter(&String.ends_with?(&1, ".png"))
      |> Enum.with_index(1)
      |> Enum.reduce_while({[], []}, fn {filename, page_num}, {texts, confidences} ->
        input_path = Path.join(preview_dir, filename)
        output_path = Path.join(pages_dir, "page-#{page_num}")
        
        case Port.run("tesseract", 
          [input_path, output_path, "--psm", "3", "-l", "eng", "--oem", "3"], 
          timeout: 30_000
        ) do
          {:ok, _} ->
            text_file = output_path <> ".txt"
            if File.exists?(text_file) do
              {:ok, page_text} = File.read(text_file)
              {:ok, confidence} = get_page_confidence(output_path, page_text)
              {:cont, {[page_text | texts], [confidence | confidences]}}
            else
              {:cont, {texts, confidences}}
            end
          {:error, _} ->
            {:cont, {texts, confidences}}
        end
      end)
      |> then(fn {texts, confidences} ->
        full_text = texts |> Enum.reverse() |> Enum.join("\n")
        avg_confidence = if confidences != [] do
          Enum.sum(confidences) / length(confidences)
        else
          0.5
        end
        
        {:ok, full_text, avg_confidence}
      end)
    else
      {:error, :no_previews}
    end
  end

  defp ocr_text_only(pdf_path, temp_dir) do
    # Convert entire PDF to image and OCR
    _image_path = Path.join(temp_dir, "full_page.png")
    
    case Port.run("pdftoppm", ["-png", "-r", "150", "-singlefile", pdf_path], 
         timeout: 60_000, cwd: temp_dir) do
      {:ok, _} ->
        # Find the generated PNG file
        png_files = File.ls!(temp_dir) |> Enum.filter(&String.ends_with?(&1, ".png"))
        
        if png_files != [] do
          image_path = Path.join(temp_dir, hd(png_files))
          
          case Port.run("tesseract", 
            [image_path, "stdout", "--psm", "3", "-l", "eng", "--oem", "3"], 
            timeout: 60_000
          ) do
            {:ok, text} ->
              {:ok, text, 0.8}  # Assume decent OCR quality
            error ->
              {:error, error}
          end
        else
          {:error, :no_output}
        end
      error ->
        {:error, error}
    end
  end

  defp get_page_confidence(output_path, _text) do
    # Try to get confidence scores via tesseract TSV output
    tsv_path = output_path <> ".tsv"
    
    case Port.run("tesseract", 
      [output_path <> ".png", output_path, "--psm", "3", "-l", "eng", "--oem", "3"], 
      timeout: 30_000
    ) do
      {:ok, _} ->
        case File.read(tsv_path) do
          {:ok, tsv_content} ->
            # Parse TSV and compute average confidence
            confidences = tsv_content
            |> String.split("\n")
            |> Enum.drop(1)  # Skip header
            |> Enum.map(fn line ->
              case line |> String.split("\t") |> Enum.at(11) do
                nil -> 0
                conf_str -> 
                  case Integer.parse(conf_str) do
                    {conf, _} -> conf / 100.0  # Normalize 0-100 to 0-1
                    :error -> 0
                  end
              end
            end)
            |> Enum.reject(&(&1 == 0))
            
            avg_conf = if confidences != [] do
              Enum.sum(confidences) / length(confidences)
            else
              0.5
            end
            
            {:ok, avg_conf}
          _ ->
            {:ok, 0.5}  # Fallback confidence
        end
      _ ->
        {:ok, 0.5}  # Fallback confidence
    end
  end

  defp build_result(text, pages, page_count, ocr, ocr_confidence, tools) do
    tools_with_versions = Map.new(tools, fn {tool, _available} ->
      version = Port.get_version(tool)
      {tool, version}
    end)
    
    %__MODULE__{
      text: text,
      pages: pages,
      page_count: page_count,
      char_count: String.length(text),
      word_count: Metrics.word_count(text),
      ocr: ocr,
      ocr_confidence: ocr_confidence,
      tools_used: tools_with_versions,
      previews_generated: Map.get(tools_with_versions, :pdftoppm) != nil
    }
  end
end
