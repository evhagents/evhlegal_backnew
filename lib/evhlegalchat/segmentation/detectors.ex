defmodule Evhlegalchat.Segmentation.Detectors do
  @moduledoc """
  Candidate detection for document segmentation.
  
  Implements various detectors for identifying clause boundaries
  including numbered headings, bullet points, and signature anchors.
  """

  require Logger
  alias Evhlegalchat.Segmentation.Types.Candidate

  @doc """
  Detects all candidates in the given text using all available detectors.
  
  Returns a list of Candidate structs sorted by character offset.
  """
  def detect_candidates(text, opts \\ []) do
    Logger.debug("Starting candidate detection", text_length: String.length(text))
    
    detectors = [
      &detect_numbered_headings/2,
      &detect_all_caps_headings/2,
      &detect_title_case_headings/2,
      &detect_bullet_points/2,
      &detect_exhibit_markers/2,
      &detect_signature_anchors/2
    ]
    
    candidates = Enum.flat_map(detectors, fn detector ->
      detector.(text, opts)
    end)
    
    # Sort by character offset
    sorted_candidates = Enum.sort_by(candidates, & &1.char_offset)
    
    Logger.debug("Candidate detection completed", 
      total_candidates: length(sorted_candidates),
      by_type: Enum.group_by(sorted_candidates, & &1.type)
    )
    
    sorted_candidates
  end

  @doc """
  Detects numbered headings with decimal, roman, or alpha numbering.
  
  Patterns:
  - Decimal: "1.", "2.1", "3.2.1"
  - Roman: "I.", "II.", "III."
  - Alpha: "a)", "b)", "c)"
  """
  def detect_numbered_headings(text, _opts) do
    # Decimal numbering pattern
    decimal_pattern = ~r/^(?<num>(\d+(\.\d+)*))[\.\)]\s+(?<title>[A-Z][^\n]{0,120})$/m
    
    # Roman numeral pattern (I through XX)
    roman_pattern = ~r/^(?<num>([IVXLCM]+(\.[IVXLCM]+)*))[\.\)]\s+(?<title>[A-Z][^\n]{0,120})$/m
    
    # Alpha pattern
    alpha_pattern = ~r/^(?<num>([a-z]+))[\.\)]\s+(?<title>[A-Z][^\n]{0,120})$/m
    
    patterns = [
      {decimal_pattern, :numbered_decimal},
      {roman_pattern, :numbered_roman},
      {alpha_pattern, :numbered_alpha}
    ]
    
    Enum.flat_map(patterns, fn {pattern, type} ->
      Regex.scan(pattern, text, return: :index)
      |> Enum.map(fn [{offset, length}, {num_offset, num_length}, {title_offset, title_length}] ->
        number_label = String.slice(text, num_offset, num_length)
        heading_text = String.slice(text, title_offset, title_length)
        
        # Calculate line index
        line_index = (String.slice(text, 0, offset) |> String.split("\n") |> length()) - 1
        
        # Base score with bonuses
        score = calculate_numbered_score(number_label, heading_text, type)
        
        %Candidate{
          char_offset: offset,
          line_index: line_index,
          type: type,
          detector: :numbered_headings,
          score: score,
          number_label: number_label,
          heading_text: heading_text
        }
      end)
    end)
  end

  @doc """
  Detects all-caps headings.
  
  Pattern: Lines starting with uppercase letters, 2-100 chars, no lowercase.
  """
  def detect_all_caps_headings(text, _opts) do
    pattern = ~r|^[A-Z][A-Z /&-]{2,100}$|m
    
    Regex.scan(pattern, text, return: :index)
    |> Enum.map(fn [{offset, length}] ->
      heading_text = String.slice(text, offset, length)
      line_index = (String.slice(text, 0, offset) |> String.split("\n") |> length()) - 1
      
      score = calculate_caps_score(heading_text)
      
      %Candidate{
        char_offset: offset,
        line_index: line_index,
        type: :all_caps_heading,
        detector: :all_caps_headings,
        score: score,
        number_label: nil,
        heading_text: heading_text
      }
    end)
  end

  @doc """
  Detects title case headings.
  
  Pattern: Lines with Title Case formatting.
  """
  def detect_title_case_headings(text, _opts) do
    pattern = ~r/^[A-Z][a-z]+(\s+[A-Z][a-z]+)*$/m
    
    Regex.scan(pattern, text, return: :index)
    |> Enum.map(fn [{offset, length}] ->
      heading_text = String.slice(text, offset, length)
      line_index = (String.slice(text, 0, offset) |> String.split("\n") |> length()) - 1
      
      score = calculate_title_case_score(heading_text)
      
      %Candidate{
        char_offset: offset,
        line_index: line_index,
        type: :title_case_heading,
        detector: :title_case_headings,
        score: score,
        number_label: nil,
        heading_text: heading_text
      }
    end)
  end

  @doc """
  Detects bullet points and list markers.
  
  Pattern: Lines starting with bullet characters or parenthesized letters/numbers.
  """
  def detect_bullet_points(text, _opts) do
    pattern = ~r/^(?:\([a-z]\)|\d+\)|[-•])\s+/m
    
    Regex.scan(pattern, text, return: :index)
    |> Enum.map(fn [{offset, length}] ->
      bullet_text = String.slice(text, offset, length)
      line_index = (String.slice(text, 0, offset) |> String.split("\n") |> length()) - 1
      
      score = calculate_bullet_score(bullet_text)
      
      %Candidate{
        char_offset: offset,
        line_index: line_index,
        type: :bullet_point,
        detector: :bullet_points,
        score: score,
        number_label: nil,
        heading_text: nil
      }
    end)
  end

  @doc """
  Detects exhibit and schedule markers.
  
  Pattern: "EXHIBIT A", "SCHEDULE 1", etc.
  """
  def detect_exhibit_markers(text, _opts) do
    pattern = ~r/^(EXHIBIT|SCHEDULE|APPENDIX)\s+[A-Z0-9]+$/m
    
    Regex.scan(pattern, text, return: :index)
    |> Enum.map(fn [{offset, length}] ->
      marker_text = String.slice(text, offset, length)
      line_index = (String.slice(text, 0, offset) |> String.split("\n") |> length()) - 1
      
      score = calculate_exhibit_score(marker_text)
      
      %Candidate{
        char_offset: offset,
        line_index: line_index,
        type: :exhibit_marker,
        detector: :exhibit_markers,
        score: score,
        number_label: nil,
        heading_text: marker_text
      }
    end)
  end

  @doc """
  Detects signature anchors and closing sections.
  
  Pattern: "IN WITNESS WHEREOF", "SIGNATURES", etc.
  """
  def detect_signature_anchors(text, _opts) do
    pattern = ~r/^(IN WITNESS WHEREOF|SIGNATURES?|EXECUTED|DATED)/m
    
    Regex.scan(pattern, text, return: :index)
    |> Enum.map(fn [{offset, length}] ->
      anchor_text = String.slice(text, offset, length)
      line_index = (String.slice(text, 0, offset) |> String.split("\n") |> length()) - 1
      
      score = calculate_signature_score(anchor_text)
      
      %Candidate{
        char_offset: offset,
        line_index: line_index,
        type: :signature_anchor,
        detector: :signature_anchors,
        score: score,
        number_label: nil,
        heading_text: anchor_text
      }
    end)
  end

  # Private scoring functions

  defp calculate_numbered_score(number_label, heading_text, type) do
    base_score = case type do
      :numbered_decimal -> 0.8
      :numbered_roman -> 0.7
      :numbered_alpha -> 0.6
    end
    
    # Bonus for proper capitalization
    caps_bonus = if String.match?(heading_text, ~r/^[A-Z]/), do: 0.1, else: 0.0
    
    # Bonus for reasonable length
    length_bonus = cond do
      String.length(heading_text) < 10 -> -0.1
      String.length(heading_text) > 100 -> -0.1
      true -> 0.0
    end
    
    clamp_score(base_score + caps_bonus + length_bonus)
  end

  defp calculate_caps_score(heading_text) do
    base_score = 0.7
    
    # Bonus for reasonable length
    length_bonus = cond do
      String.length(heading_text) < 5 -> -0.2
      String.length(heading_text) > 50 -> -0.1
      true -> 0.1
    end
    
    # Bonus for common legal terms
    legal_bonus = if String.contains?(heading_text, ~w(DEFINITIONS TERMS CONDITIONS AGREEMENT)), do: 0.1, else: 0.0
    
    clamp_score(base_score + length_bonus + legal_bonus)
  end

  defp calculate_title_case_score(heading_text) do
    base_score = 0.6
    
    # Bonus for proper title case
    title_case_bonus = if String.match?(heading_text, ~r/^[A-Z][a-z]+(\s+[A-Z][a-z]+)*$/), do: 0.1, else: 0.0
    
    # Bonus for reasonable length
    length_bonus = cond do
      String.length(heading_text) < 5 -> -0.2
      String.length(heading_text) > 50 -> -0.1
      true -> 0.0
    end
    
    clamp_score(base_score + title_case_bonus + length_bonus)
  end

  defp calculate_bullet_score(bullet_text) do
    base_score = 0.5
    
    # Different scores for different bullet types
    type_bonus = case String.first(bullet_text) do
      "•" -> 0.1
      "-" -> 0.0
      "(" -> 0.1
      "[" -> 0.1
      _ -> 0.0
    end
    
    clamp_score(base_score + type_bonus)
  end

  defp calculate_exhibit_score(marker_text) do
    base_score = 0.9  # High confidence for exhibit markers
    
    # Bonus for proper formatting
    format_bonus = if String.match?(marker_text, ~r/^(EXHIBIT|SCHEDULE|APPENDIX)\s+[A-Z0-9]+$/), do: 0.1, else: 0.0
    
    clamp_score(base_score + format_bonus)
  end

  defp calculate_signature_score(anchor_text) do
    base_score = 0.8  # High confidence for signature anchors
    
    # Bonus for complete phrases
    phrase_bonus = if String.contains?(anchor_text, "WITNESS"), do: 0.1, else: 0.0
    
    clamp_score(base_score + phrase_bonus)
  end

  defp clamp_score(score) when score > 1.0, do: 1.0
  defp clamp_score(score) when score < 0.0, do: 0.0
  defp clamp_score(score), do: score
end