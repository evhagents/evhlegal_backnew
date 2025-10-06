defmodule Evhlegalchat.Segmentation.Reconcile do
  @moduledoc """
  Candidate reconciliation and suppression logic.
  
  Takes detected candidates and applies overlap suppression,
  minimum distance rules, and final scoring to produce
  finalized clause boundaries.
  """

  require Logger
  alias Evhlegalchat.Segmentation.Types.Candidate

  @doc """
  Reconciles candidates applying overlap suppression and scoring.
  
  Takes a sorted list of candidates and returns processed boundaries.
  """
  def reconcile_candidates(candidates, opts \\ []) do
    overlap_window = Keyword.get(opts, :overlap_window, 30)
    min_boundary_gap = Keyword.get(opts, :min_boundary_gap, 80)
    accept_threshold = Keyword.get(opts, :accept_threshold, 0.75)
    
    Logger.debug("Starting candidate reconciliation", 
      total_candidates: length(candidates),
      overlap_window: overlap_window,
      min_boundary_gap: min_boundary_gap,
      accept_threshold: accept_threshold
    )
    
    # Sort by character offset
    sorted_candidates = Enum.sort_by(candidates, & &1.char_offset)
    
    # Apply overlap suppression
    {accepted_candidates, suppressed_candidates} = suppress_overlaps(sorted_candidates, overlap_window)
    
    # Apply minimum distance enforcement
    spaced_candidates = enforce_minimum_distance(accepted_candidates, min_boundary_gap)
    
    # Filter by acceptance threshold
    final_candidates = Enum.filter(spaced_candidates, fn candidate ->
      candidate.score >= accept_threshold
    end)
    
    Logger.debug("Candidate reconciliation completed",
      accepted: length(final_candidates),
      suppressed: length(suppressed_candidates)
    )
    
    {final_candidates, suppressed_candidates}
  end

  @doc """
  Suppresses overlapping candidates within the given window.
  
  Keeps higher-scoring candidates when overlaps occur.
  """
  def suppress_overlaps(candidates, overlap_window) when overlap_window > 0 do
    suppress_overlaps_recursive(candidates, overlap_window, [], [])
  end

  @doc """
  Enforces minimum distance between accepted boundaries.
  
  Prevents clustering of boundaries in dense text regions.
  """
  def enforce_minimum_distance(candidates, min_gap) when min_gap > 0 do
    enforce_distance_recursive(candidates, min_gap, [])
  end

  @doc """
  Applies context-based scoring adjustments to candidates.
  
  Considers surrounding text, OCR quality, and other contextual factors.
  """
  def apply_context_scoring(candidates, text, opts \\ []) do
    ocr_used = Keyword.get(opts, :ocr_used, false)
    ocr_low_conf_penalty = Keyword.get(opts, :ocr_low_conf_penalty, 0.2)
    
    Enum.map(candidates, fn candidate ->
      adjusted_score = score_candidate_with_context(candidate, text, %{
        ocr_used: ocr_used,
        ocr_low_conf_penalty: ocr_low_conf_penalty
      })
      
      %{candidate | score: adjusted_score}
    end)
  end

  # Private functions

  defp suppress_overlaps_recursive([], _window, accepted, suppressed) do
    {Enum.reverse(accepted), Enum.reverse(suppressed)}
  end
  
  defp suppress_overlaps_recursive([current | remaining], window, accepted, suppressed) do
    # Find overlapping candidates within window
    overlaps = Enum.take_while(remaining, fn candidate ->
      candidate.char_offset - current.char_offset <= window
    end)
    
    # Determine if current should be kept or suppressed
    all_candidates_in_window = [current | overlaps]
    best_candidate = Enum.max_by(all_candidates_in_window, & &1.score)
    
    if best_candidate.char_offset == current.char_offset do
      # Current is best, add it to accepted
      suppress_overlaps_recursive(remaining, window, [current | accepted], suppressed)
    else
      # Current overlaps with something better, suppress it
      suppress_overlaps_recursive(remaining, window, accepted, [current | suppressed])
    end
  end

  defp enforce_distance_recursive([], _min_gap, result) do
    Enum.reverse(result)
  end
  
  defp enforce_distance_recursive([current | remaining], min_gap, result) do
    case result do
      [] ->
        # First candidate is always accepted
        enforce_distance_recursive(remaining, min_gap, [current | result])
      
      [last_accepted | _rest] ->
        gap = current.char_offset - last_accepted.char_offset
        
        if gap >= min_gap do
          # Sufficient gap, accept this candidate
          enforce_distance_recursive(remaining, min_gap, [current | result])
        else
          # Insufficient gap, skip this candidate
          enforce_distance_recursive(remaining, min_gap, result)
        end
    end
  end

  defp score_candidate_with_context(candidate, text, context_opts) do
    base_score = candidate.score
    
    # Apply context-based scoring adjustments
    context_adjustments = [
      check_start_of_line_bonus(candidate, text),
      check_blank_line_bonus(candidate, text),
      check_title_case_bonus(candidate),
      check_number_sequence_bonus(candidate, text),
      check_ocr_penalty(candidate, context_opts)
    ]
    
    adjusted_score = base_score + Enum.sum(context_adjustments)
    clamp_score(adjusted_score)
  end

  defp check_start_of_line_bonus(candidate, text) do
    # Check if candidate is at start of line
    if candidate.char_offset == 0 or String.at(text, candidate.char_offset - 1) == "\n" do
      0.15
    else
      0.0
    end
  end

  defp check_blank_line_bonus(candidate, text) do
    # Check for blank lines before/after
    before_blank = check_blank_line_before(candidate, text)
    after_blank = check_blank_line_after(candidate, text)
    
    if before_blank and after_blank do
      0.15
    else
      0.0
    end
  end

  defp check_blank_line_before(candidate, text) do
    # Look for blank line before candidate
    start_search = max(0, candidate.char_offset - 200)
    before_text = String.slice(text, start_search, candidate.char_offset - start_search)
    
    String.contains?(before_text, "\n\n") or String.contains?(before_text, "\n\r\n")
  end

  defp check_blank_line_after(candidate, text) do
    # Look for blank line after candidate
    end_search = min(String.length(text), candidate.char_offset + 200)
    after_text = String.slice(text, candidate.char_offset, end_search - candidate.char_offset)
    
    String.contains?(after_text, "\n\n") or String.contains?(after_text, "\n\r\n")
  end

  defp check_title_case_bonus(candidate) do
    case candidate.type do
      :title_case_heading -> 0.2
      :all_caps_heading -> 0.2
      _ -> 0.0
    end
  end

  defp check_number_sequence_bonus(candidate, text) do
    # Check if this candidate follows a logical number sequence
    case candidate.type do
      type when type in [:numbered_decimal, :numbered_roman, :numbered_alpha] ->
        if valid_number_sequence?(candidate, text) do
          0.15
        else
          0.0
        end
      _ ->
        0.0
    end
  end

  defp valid_number_sequence?(candidate, text) do
    # This would implement number sequence validation
    # For now, return true for numbered candidates
    candidate.number_label != nil
  end

  defp check_ocr_penalty(candidate, context_opts) do
    case context_opts do
      %{ocr_used: true, ocr_low_conf_penalty: penalty} ->
        -penalty
      _ ->
        0.0
    end
  end

  defp clamp_score(score) when score > 1.0, do: 1.0
  defp clamp_score(score) when score < 0.0, do: 0.0
  defp clamp_score(score), do: score
end