defmodule Evhlegalchat.Segmentation.Anomalies do
  @moduledoc """
  Anomaly detection for segmentation results.
  
  Identifies various issues and inconsistencies in detected
  clause boundaries and numbering patterns.
  """

  require Logger
  alias Evhlegalchat.Segmentation.Types.{Anomaly, Clause}
  alias Evhlegalchat.Segmentation.Normalize

  @doc """
  Detects all anomalies in the given clauses.
  
  Returns a list of Anomaly structs with type, location, and severity.
  """
  def detect_anomalies(clauses, opts \\ []) do
    Logger.debug("Starting anomaly detection", clause_count: length(clauses))
    
    anomaly_detectors = [
      &detect_duplicate_numbers/2,
      &detect_skipped_numbers/2,
      &detect_unheaded_blocks/2,
      &detect_excessive_short_clauses/2,
      &detect_page_regressions/2,
      &detect_mixed_numbering/2,
      &detect_all_lowercase_headings/2,
      &detect_sparse_boundaries/2,
      &detect_low_confidence_boundaries/2
    ]
    
    anomalies = Enum.flat_map(anomaly_detectors, fn detector ->
      detector.(clauses, opts)
    end)
    
    Logger.debug("Anomaly detection completed", 
      total_anomalies: length(anomalies),
      by_type: Enum.group_by(anomalies, & &1.type)
    )
    
    anomalies
  end

  @doc """
  Detects duplicate number labels in clauses.
  
  Identifies cases where the same number appears multiple times.
  """
  def detect_duplicate_numbers(clauses, _opts) do
    clauses
    |> Enum.filter(fn clause -> clause.number_label != nil end)
    |> Enum.group_by(fn clause -> clause.number_label end)
    |> Enum.filter(fn {_label, clause_list} -> length(clause_list) > 1 end)
    |> Enum.flat_map(fn {label, clause_list} ->
      Enum.map(clause_list, fn clause ->
        %Anomaly{
          type: :duplicate_number,
          at: clause.start_char,
          severity: :medium,
          description: "Duplicate number label '#{label}'"
        }
      end)
    end)
  end

  @doc """
  Detects skipped numbers in sequence.
  
  Identifies gaps in numbering sequences.
  """
  def detect_skipped_numbers(clauses, _opts) do
    numbered_clauses = clauses
    |> Enum.filter(fn clause -> clause.number_label != nil end)
    |> Enum.sort_by(fn clause -> Normalize.extract_numeric_value(clause.number_label) end)
    
    numbered_clauses
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [prev_clause, next_clause] ->
      prev_val = Normalize.extract_numeric_value(prev_clause.number_label)
      next_val = Normalize.extract_numeric_value(next_clause.number_label)
      
      if next_val - prev_val > 1 do
        [%Anomaly{
          type: :skipped_number,
          at: next_clause.start_char,
          severity: :low,
          description: "Skipped number between '#{prev_clause.number_label}' and '#{next_clause.number_label}'"
        }]
      else
        []
      end
    end)
  end

  @doc """
  Detects unheaded blocks (large text segments without headings).
  
  Identifies sections that may need better segmentation.
  """
  def detect_unheaded_blocks(clauses, opts) do
    min_block_size = Keyword.get(opts, :min_unheaded_block_size, 500)
    
    clauses
    |> Enum.filter(fn clause -> clause.heading_text == nil or clause.heading_text == "" end)
    |> Enum.filter(fn clause -> clause.end_char - clause.start_char > min_block_size end)
    |> Enum.map(fn clause ->
      %Anomaly{
        type: :unheaded_block,
        at: clause.start_char,
        severity: :medium,
        description: "Large unheaded block (#{clause.end_char - clause.start_char} chars)"
      }
    end)
  end

  @doc """
  Detects excessive short clauses.
  
  Identifies clauses that may be over-segmented.
  """
  def detect_excessive_short_clauses(clauses, opts) do
    min_clause_size = Keyword.get(opts, :min_clause_size, 50)
    max_short_clause_ratio = Keyword.get(opts, :max_short_clause_ratio, 0.3)
    
    short_clauses = Enum.filter(clauses, fn clause ->
      clause.end_char - clause.start_char < min_clause_size
    end)
    
    short_ratio = length(short_clauses) / max(length(clauses), 1)
    
    if short_ratio > max_short_clause_ratio do
      Enum.map(short_clauses, fn clause ->
        %Anomaly{
          type: :excessive_short_clause,
          at: clause.start_char,
          severity: :low,
          description: "Short clause (#{clause.end_char - clause.start_char} chars)"
        }
      end)
    else
      []
    end
  end

  @doc """
  Detects page regressions (clauses spanning backwards across pages).
  
  Identifies clauses that may have incorrect page boundaries.
  """
  def detect_page_regressions(clauses, _opts) do
    clauses
    |> Enum.filter(fn clause -> clause.start_page > clause.end_page end)
    |> Enum.map(fn clause ->
      %Anomaly{
        type: :page_regression,
        at: clause.start_char,
        severity: :high,
        description: "Page regression: starts page #{clause.start_page}, ends page #{clause.end_page}"
      }
    end)
  end

  @doc """
  Detects mixed roman and decimal numbering.
  
  Identifies inconsistent numbering styles within the document.
  """
  def detect_mixed_numbering(clauses, _opts) do
    numbered_clauses = Enum.filter(clauses, fn clause -> clause.number_label != nil end)
    
    has_roman = Enum.any?(numbered_clauses, fn clause ->
      Regex.match?(~r/^[IVXLCM]+$/, String.upcase(clause.number_label))
    end)
    
    has_decimal = Enum.any?(numbered_clauses, fn clause ->
      Regex.match?(~r/^\d+/, clause.number_label)
    end)
    
    if has_roman and has_decimal do
      [%Anomaly{
        type: :mixed_roman_decimal,
        at: 0,
        severity: :medium,
        description: "Mixed roman and decimal numbering styles detected"
      }]
    else
      []
    end
  end

  @doc """
  Detects all lowercase headings.
  
  Identifies headings that may need capitalization.
  """
  def detect_all_lowercase_headings(clauses, _opts) do
    clauses
    |> Enum.filter(fn clause -> clause.heading_text != nil end)
    |> Enum.filter(fn clause ->
      heading = clause.heading_text
      String.downcase(heading) == heading and String.length(heading) > 3
    end)
    |> Enum.map(fn clause ->
      %Anomaly{
        type: :all_lowercase_heading,
        at: clause.start_char,
        severity: :low,
        description: "All lowercase heading: '#{clause.heading_text}'"
      }
    end)
  end

  @doc """
  Detects sparse boundaries (too few boundaries detected).
  
  Identifies documents that may be under-segmented.
  """
  def detect_sparse_boundaries(clauses, opts) do
    min_boundaries_for_large_doc = Keyword.get(opts, :min_boundaries_for_large_doc, 3)
    large_doc_pages = Keyword.get(opts, :large_doc_pages, 5)
    
    # Check if document is large and has few boundaries
    max_page = Enum.max_by(clauses, & &1.end_page, fn -> %{end_page: 1} end).end_page
    
    if max_page >= large_doc_pages and length(clauses) < min_boundaries_for_large_doc do
      [%Anomaly{
        type: :sparse_boundaries,
        at: 0,
        severity: :high,
        description: "Large document (#{max_page} pages) with only #{length(clauses)} boundaries"
      }]
    else
      []
    end
  end

  @doc """
  Detects low confidence boundaries.
  
  Identifies boundaries that may need review.
  """
  def detect_low_confidence_boundaries(clauses, opts) do
    review_threshold = Keyword.get(opts, :review_threshold, 0.4)
    max_low_conf_ratio = Keyword.get(opts, :max_low_conf_ratio, 0.25)
    
    low_conf_clauses = Enum.filter(clauses, fn clause ->
      clause.confidence_boundary < review_threshold
    end)
    
    low_conf_ratio = length(low_conf_clauses) / max(length(clauses), 1)
    
    if low_conf_ratio > max_low_conf_ratio do
      Enum.map(low_conf_clauses, fn clause ->
        %Anomaly{
          type: :low_confidence_boundaries,
          at: clause.start_char,
          severity: :medium,
          description: "Low confidence boundary (#{Float.round(clause.confidence_boundary, 2)})"
        }
      end)
    else
      []
    end
  end

  @doc """
  Determines if segmentation needs review based on anomalies.
  
  Returns true if the segmentation should be flagged for human review.
  """
  def needs_review?(clauses, anomalies, opts) do
    review_rules = [
      &check_sparse_boundaries_review/3,
      &check_low_confidence_review/3,
      &check_high_severity_anomalies/3,
      &check_ocr_quality_review/3
    ]
    
    Enum.any?(review_rules, fn rule ->
      rule.(clauses, anomalies, opts)
    end)
  end

  # Private review rule functions

  defp check_sparse_boundaries_review(clauses, _anomalies, opts) do
    min_boundaries_for_large_doc = Keyword.get(opts, :min_boundaries_for_large_doc, 3)
    large_doc_pages = Keyword.get(opts, :large_doc_pages, 5)
    
    max_page = Enum.max_by(clauses, & &1.end_page, fn -> %{end_page: 1} end).end_page
    
    max_page >= large_doc_pages and length(clauses) < min_boundaries_for_large_doc
  end

  defp check_low_confidence_review(_clauses, anomalies, opts) do
    review_threshold = Keyword.get(opts, :review_threshold, 0.4)
    
    low_conf_anomalies = Enum.filter(anomalies, fn anomaly ->
      anomaly.type == :low_confidence_boundaries
    end)
    
    length(low_conf_anomalies) > 0
  end

  defp check_high_severity_anomalies(_clauses, anomalies, _opts) do
    high_severity_anomalies = Enum.filter(anomalies, fn anomaly ->
      anomaly.severity == :high
    end)
    
    length(high_severity_anomalies) > 0
  end

  defp check_ocr_quality_review(_clauses, _anomalies, opts) do
    ocr_used = Keyword.get(opts, :ocr_used, false)
    ocr_confidence = Keyword.get(opts, :ocr_confidence, 1.0)
    
    ocr_used and ocr_confidence < 0.6
  end
end
