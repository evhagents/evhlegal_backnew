defmodule Evhlegalchat.Segmentation do
  @moduledoc """
  Main segmentation pipeline for document clause detection.
  
  Orchestrates the complete segmentation process from text input
  to finalized clause boundaries with anomaly detection.
  """

  require Logger
  alias Evhlegalchat.Segmentation.{
    Detectors,
    Reconcile,
    Anchors,
    Normalize,
    Anomalies,
    Types
  }

  @doc """
  Runs the complete segmentation pipeline.
  
  Takes concatenated text and page data, returns structured clause boundaries.
  
  ## Parameters
  
  - `concat_text`: Full document text from concatenated.txt
  - `pages`: List of page data with char_count from pages.jsonl
  - `opts`: Options including OCR status, thresholds, etc.
  
  ## Returns
  
  %SegResult{} with clauses, metrics, anomalies, events, and needs_review flag.
  """
  def run(concat_text, pages, opts \\ []) do
    Logger.info("Starting segmentation pipeline", 
      text_length: String.length(concat_text),
      page_count: length(pages)
    )

    # Parse options
    segmentation_version = Keyword.get(opts, :segmentation_version, "seg-v1.0")
    ocr_used = Keyword.get(opts, :ocr_used, false)
    ocr_confidence = Keyword.get(opts, :ocr_confidence, 1.0)
    
    # Build page index for efficient lookups
    page_index = Anchors.build_page_index(pages)
    
    # Step 1: Canvas normalization
    normalized_text = normalize_canvas(concat_text)
    
    # Step 2: Candidate detection
    candidates = Detectors.detect_candidates(normalized_text, opts)
    
    # Step 3: Context scoring
    scored_candidates = Reconcile.apply_context_scoring(candidates, normalized_text, opts)
    
    # Step 4: Reconciliation
    {accepted_candidates, suppressed_candidates} = Reconcile.reconcile_candidates(scored_candidates, opts)
    
    # Step 5: Build clauses
    clauses = build_clauses(accepted_candidates, normalized_text, page_index, opts)
    
    # Step 6: Anomaly detection
    anomalies = Anomalies.detect_anomalies(clauses, opts)
    
    # Step 7: Compute metrics
    metrics = compute_metrics(candidates, accepted_candidates, suppressed_candidates, ocr_used)
    
    # Step 8: Generate events
    events = generate_events(candidates, accepted_candidates, suppressed_candidates, anomalies)
    
    # Step 9: Determine if review is needed
    needs_review = Anomalies.needs_review?(clauses, anomalies, opts)
    
    result = %Types.SegResult{
      clauses: clauses,
      metrics: metrics,
      anomalies: anomalies,
      events: events,
      needs_review: needs_review
    }
    
    Logger.info("Segmentation pipeline completed",
      clause_count: length(clauses),
      anomaly_count: length(anomalies),
      needs_review: needs_review
    )
    
    result
  end

  # Private functions

  defp normalize_canvas(text) do
    # Normalize line breaks and paragraph boundaries
    text
    |> String.replace(~r/\r\n|\r/, "\n")  # Normalize line endings
    |> String.replace(~r/\n{3,}/, "\n\n")  # Collapse multiple newlines
    |> String.trim()
  end

  defp build_clauses(candidates, text, page_index, opts) do
    # Sort candidates by character offset
    sorted_candidates = Enum.sort_by(candidates, & &1.char_offset)
    
    # Build clauses from candidates
    clauses = sorted_candidates
    |> Enum.with_index(1)
    |> Enum.map(fn {candidate, ordinal} ->
      build_clause_from_candidate(candidate, ordinal, text, page_index, opts)
    end)
    
    # Add final clause to end of document
    final_clause = build_final_clause(clauses, text, page_index)
    
    clauses ++ [final_clause]
  end

  defp build_clause_from_candidate(candidate, ordinal, text, page_index, opts) do
    # Determine clause boundaries
    start_char = candidate.char_offset
    end_char = determine_clause_end(candidate, text, opts)
    
    # Map to page numbers
    {start_page, end_page} = Anchors.char_range_to_page_range(start_char, end_char, page_index)
    
    # Extract text snippet
    text_snippet = extract_text_snippet(text, start_char, end_char)
    
    # Compute confidence scores
    confidence_boundary = compute_boundary_confidence(candidate, text)
    confidence_heading = compute_heading_confidence(candidate)
    
    # Normalize number label
    normalized_number_label = if candidate.number_label do
      Normalize.normalize_number_label(candidate.number_label)
    else
      nil
    end
    
    # Map detected style
    detected_style = map_detected_style(candidate.type)
    
    %Types.Clause{
      ordinal: ordinal,
      number_label: normalized_number_label,
      heading_text: candidate.heading_text,
      start_char: start_char,
      end_char: end_char,
      start_page: start_page,
      end_page: end_page,
      detected_style: detected_style,
      confidence_boundary: confidence_boundary,
      confidence_heading: confidence_heading,
      anomaly_flags: [],
      text_snippet: text_snippet
    }
  end

  defp determine_clause_end(candidate, text, opts) do
    # Find the next candidate or end of document
    next_candidate_offset = find_next_candidate_offset(candidate.char_offset, text)
    
    if next_candidate_offset do
      next_candidate_offset - 1
    else
      String.length(text) - 1
    end
  end

  defp find_next_candidate_offset(current_offset, text) do
    # This would find the next candidate offset
    # For now, use a simple approach
    remaining_text = String.slice(text, current_offset + 1, String.length(text) - current_offset - 1)
    
    case Regex.run(~r"^(?:\d+\.|[IVXLCM]+\.|[A-Z][A-Z /&-]{2,100})$"m, remaining_text, return: :index) do
      [{offset, _length}] ->
        current_offset + 1 + offset
      _ ->
        nil
    end
  end

  defp build_final_clause(clauses, text, page_index) do
    # Create final clause from last candidate to end of document
    last_clause = List.last(clauses)
    start_char = if last_clause, do: last_clause.end_char + 1, else: 0
    end_char = String.length(text) - 1
    
    {start_page, end_page} = Anchors.char_range_to_page_range(start_char, end_char, page_index)
    
    text_snippet = extract_text_snippet(text, start_char, end_char)
    
    %Types.Clause{
      ordinal: length(clauses) + 1,
      number_label: nil,
      heading_text: nil,
      start_char: start_char,
      end_char: end_char,
      start_page: start_page,
      end_page: end_page,
      detected_style: :unheaded_block,
      confidence_boundary: 0.5,
      confidence_heading: 0.0,
      anomaly_flags: [],
      text_snippet: text_snippet
    }
  end

  defp extract_text_snippet(text, start_char, end_char) do
    snippet_length = min(200, end_char - start_char + 1)
    
    text
    |> String.slice(start_char, snippet_length)
    |> String.replace(~r/\n/, " ")  # Replace newlines with spaces
    |> String.trim()
  end

  defp compute_boundary_confidence(candidate, text) do
    # Base confidence from candidate score
    base_confidence = candidate.score
    
    # Adjust based on surrounding text
    context_adjustment = compute_context_adjustment(candidate, text)
    
    clamp_confidence(base_confidence + context_adjustment)
  end

  defp compute_context_adjustment(candidate, text) do
    # Check for proper capitalization
    caps_adjustment = if candidate.heading_text do
      if String.match?(candidate.heading_text, ~r/^[A-Z]/) do
        0.1
      else
        -0.1
      end
    else
      0.0
    end
    
    # Check for proper spacing
    spacing_adjustment = check_spacing_quality(candidate, text)
    
    caps_adjustment + spacing_adjustment
  end

  defp check_spacing_quality(candidate, text) do
    # Check for blank lines before/after
    before_blank = check_blank_line_before(candidate.char_offset, text)
    after_blank = check_blank_line_after(candidate.char_offset, text)
    
    cond do
      before_blank and after_blank -> 0.1
      before_blank or after_blank -> 0.05
      true -> 0.0
    end
  end

  defp check_blank_line_before(offset, text) do
    start_search = max(0, offset - 100)
    before_text = String.slice(text, start_search, offset - start_search)
    String.contains?(before_text, "\n\n")
  end

  defp check_blank_line_after(offset, text) do
    end_search = min(String.length(text), offset + 100)
    after_text = String.slice(text, offset, end_search - offset)
    String.contains?(after_text, "\n\n")
  end

  defp compute_heading_confidence(candidate) do
    case candidate.heading_text do
      nil -> 0.0
      heading ->
        base_confidence = case candidate.type do
          :all_caps_heading -> 0.8
          :title_case_heading -> 0.7
          :numbered_decimal -> 0.9
          :numbered_roman -> 0.8
          _ -> 0.6
        end
        
        # Adjust for heading length
        length_adjustment = cond do
          String.length(heading) < 5 -> -0.2
          String.length(heading) > 50 -> -0.1
          true -> 0.0
        end
        
        clamp_confidence(base_confidence + length_adjustment)
    end
  end

  defp map_detected_style(candidate_type) do
    case candidate_type do
      :numbered_decimal -> :numbered_decimal
      :numbered_roman -> :numbered_roman
      :numbered_alpha -> :numbered_alpha
      :bullet_point -> :bullet_point
      :all_caps_heading -> :all_caps_heading
      :title_case_heading -> :title_case_heading
      :exhibit_marker -> :exhibit_marker
      :signature_anchor -> :signature_anchor
      _ -> :unheaded_block
    end
  end

  defp compute_metrics(candidates, accepted_candidates, suppressed_candidates, ocr_used) do
    candidate_count = length(candidates)
    accepted_count = length(accepted_candidates)
    suppressed_count = length(suppressed_candidates)
    
    mean_conf_boundary = if accepted_count > 0 do
      accepted_candidates
      |> Enum.map(& &1.score)
      |> Enum.sum()
      |> Kernel./(accepted_count)
    else
      0.0
    end
    
    %Types.Metrics{
      candidate_count: candidate_count,
      accepted_count: accepted_count,
      suppressed_count: suppressed_count,
      mean_conf_boundary: mean_conf_boundary,
      ocr_used: ocr_used
    }
  end

  defp generate_events(candidates, accepted_candidates, suppressed_candidates, anomalies) do
    timestamp = DateTime.utc_now()
    
    events = [
      %Types.Event{
        event: :boundary_detected,
        timestamp: timestamp,
        detail: %{total_candidates: length(candidates)}
      },
      %Types.Event{
        event: :boundaries_accepted,
        timestamp: timestamp,
        detail: %{accepted_count: length(accepted_candidates)}
      },
      %Types.Event{
        event: :boundaries_suppressed,
        timestamp: timestamp,
        detail: %{suppressed_count: length(suppressed_candidates)}
      }
    ]
    
    # Add anomaly events
    anomaly_events = Enum.map(anomalies, fn anomaly ->
      %Types.Event{
        event: :anomaly_detected,
        timestamp: timestamp,
        detail: %{type: anomaly.type, severity: anomaly.severity}
      }
    end)
    
    events ++ anomaly_events
  end

  defp clamp_confidence(confidence) when confidence > 1.0, do: 1.0
  defp clamp_confidence(confidence) when confidence < 0.0, do: 0.0
  defp clamp_confidence(confidence), do: confidence
end