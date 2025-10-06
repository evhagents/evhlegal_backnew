defmodule Evhlegalchat.Ingest.Extract.Metrics do
  @moduledoc """
  Metrics computation for extracted text content.
  
  Provides word counting, language detection, and quality metrics
  for processed document content.
  """

  require Logger

  @doc """
  Computes word count from text content.
  
  Uses whitespace-based word splitting with basic normalization.
  """
  def word_count(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.split(~r/\s+/)
    |> Enum.reject(fn word -> word == "" end)
    |> length()
  end

  @doc """
  Detects language of text content using simple heuristics.
  
  Returns language code (e.g., "en", "de", "fr") or "unknown".
  Only analyzes first 5000 characters for performance.
  """
  def detect_language(text) when is_binary(text) do
    # Limit to first 5000 characters for performance
    sample_text = String.slice(text, 0, 5000)
    
    # Simple language detection based on common words
    english_words = ["the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"]
    german_words = ["der", "die", "das", "und", "oder", "aber", "in", "auf", "zu", "für", "von", "mit"]
    french_words = ["le", "la", "les", "et", "ou", "mais", "dans", "sur", "à", "pour", "de", "avec"]
    
    words = sample_text
    |> String.downcase()
    |> String.split(~r/\s+/)
    |> Enum.take(100)  # Check first 100 words
    
    english_count = Enum.count(words, &(&1 in english_words))
    german_count = Enum.count(words, &(&1 in german_words))
    french_count = Enum.count(words, &(&1 in french_words))
    
    cond do
      english_count > german_count and english_count > french_count and english_count > 2 ->
        "en"
      german_count > english_count and german_count > french_count and german_count > 2 ->
        "de"
      french_count > english_count and french_count > german_count and french_count > 2 ->
        "fr"
      true ->
        "unknown"
    end
  end

  @doc """
  Computes comprehensive metrics for extracted content.
  
  Returns a map with standardized metric values.
  """
  def compute_metrics(extract_result, opts \\ []) do
    include_previews = Keyword.get(opts, :include_previews, false)
    preview_page_count = if include_previews, do: Keyword.get(opts, :preview_page_count, 0), else: nil
    
    base_metrics = %{
      "page_count" => extract_result.page_count,
      "char_count" => extract_result.char_count,
      "word_count" => extract_result.word_count,
      "language" => detect_language(extract_result.text)
    }

    # Add OCR-specific metrics if OCR was used
    metrics = if extract_result.ocr do
      Map.put(base_metrics, "ocr", true)
      |> Map.put("ocr_confidence", extract_result.ocr_confidence)
      |> Map.put("avg_chars_per_page", compute_avg_chars_per_page(extract_result.page_count, extract_result.char_count))
    else
      Map.put(base_metrics, "ocr", false)
      |> Map.put("avg_chars_per_page", compute_avg_chars_per_page(extract_result.page_count, extract_result.char_count))
    end

    # Add tool versions
    metrics = Map.put(metrics, "tools_used", extract_result.tools_used)

    # Add preview information if applicable
    metrics = if preview_page_count && preview_page_count > 0 do
      Map.put(metrics, "previews_generated", preview_page_count)
    else
      metrics
    end

    # Remove nil values
    Enum.reject(metrics, fn {_k, v} -> is_nil(v) end) |> Enum.into(%{})
  end

  @doc """
  Validates that metrics contain required fields.
  
  Returns true if metrics are valid, false otherwise.
  """
  def validate_metrics?(metrics) when is_map(metrics) do
    required_fields = ["page_count", "char_count"]
    
    Enum.all?(required_fields, fn field ->
      case Map.get(metrics, field) do
        value when is_number(value) and value > 0 -> true
        _ -> false
      end
    end)
  end

  @doc """
  Checks if content quality is sufficient for processing.
  
  Returns {:ok, :good} or {:warning, reason} or {:error, reason}.
  """
  def assess_content_quality(extract_result) do
    cond do
      extract_result.char_count == 0 ->
        {:error, :empty_content}
      
      extract_result.char_count < 10 ->
        {:warning, :minimal_content}
      
      extract_result.page_count > 1000 ->
        {:warning, :very_long_document}
      
      extract_result.ocr && extract_result.ocr_confidence && extract_result.ocr_confidence < 0.5 ->
        {:warning, :low_ocr_confidence}
      
      true ->
        {:ok, :good}
    end
  end

  @doc """
  Generates quality signals for the staging upload metadata.
  
  Returns a map suitable for including in staging_uploads.metadata.
  """
  def quality_signals(extract_result) do
    %{
      "content_quality" => assess_content_quality(extract_result),
      "has_structured_content" => has_structured_content?(extract_result.text),
      "text_density_percentage" => text_density_percentage(extract_result.text),
      "predicted_document_type" => predict_document_type(extract_result)
    }
  end

  # Private functions

  defp compute_avg_chars_per_page(page_count, char_count) when page_count > 0 do
    round(char_count / page_count)
  end
  defp compute_avg_chars_per_page(_page_count, char_count) do
    char_count
  end

  defp has_structured_content?(text) do
    # Look for common document structure indicators
    struct_indicators = [
      ~r/(?:^|\n)\s*(?:Chapter|Section|Article|Clause|Paragraph)\s+\d+/i,
      ~r/(?:^|\n)\s*\d+\.\d*/,  # Numbered lists
      ~r/(?:^|\n)\s*[A-Z][^.]{20,}\.?\s*$/m,  # Possible headers
      ~r/(?:^|\n)\s*(?:Party|Company|Address):\s*\n/mi
    ]
    
    Enum.any?(struct_indicators, fn pattern ->
      Regex.match?(pattern, text)
    end)
  end

  defp text_density_percentage(text) do
    total_chars = String.length(text)
    text_chars = text
    |> String.replace(~r/\s/, "")
    |> String.length()
    
    if total_chars > 0 do
      round(text_chars / total_chars * 100)
    else
      0
    end
  end

  defp predict_document_type(extract_result) do
    text = extract_result.text
    
    cond do
      String.contains?(text, "non-disclosure agreement") or String.contains?(text, "NDA") ->
        "nda"
      String.contains?(text, "terms of service") or String.contains?(text, "terms and conditions") ->
        "terms"
      String.contains?(text, "privacy policy") ->
        "privacy"
      String.contains?(text, "agreement") ->
        "agreement"
      true ->
        "unknown"
    end
  end
end
