defmodule Evhlegalchat.Promotion.DocType do
  @moduledoc """
  Document type detection for legal documents.
  
  Analyzes clause headings and content to determine if a document
  is an NDA, SOW, or other type.
  """

  @doc """
  Guesses document type from clause analysis.
  
  Returns {:ok, :NDA | :SOW} or {:unknown, default: :NDA}.
  """
  def guess(clauses) when is_list(clauses) do
    # Extract text from first few clauses for analysis
    text_samples = clauses
    |> Enum.take(3)
    |> Enum.flat_map(fn clause ->
      [clause.heading_text, clause.text_snippet]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()

    nda_score = calculate_nda_score(text_samples)
    sow_score = calculate_sow_score(text_samples)
    
    cond do
      nda_score > sow_score and nda_score > 0 ->
        {:ok, :NDA}
      sow_score > nda_score and sow_score > 0 ->
        {:ok, :SOW}
      true ->
        {:unknown, default: :NDA}
    end
  end

  # Private functions

  defp calculate_nda_score(text) do
    nda_keywords = [
      "non-disclosure agreement",
      "confidentiality agreement", 
      "nda",
      "confidential information",
      "proprietary information",
      "trade secrets",
      "disclosure",
      "confidentiality",
      "non-disclosure",
      "proprietary",
      "confidential"
    ]
    
    sow_keywords = [
      "statement of work",
      "scope of work",
      "deliverables",
      "milestones",
      "sow",
      "work order",
      "project scope"
    ]
    
    nda_matches = count_keyword_matches(text, nda_keywords)
    sow_matches = count_keyword_matches(text, sow_keywords)
    
    # Boost NDA score if we find strong NDA indicators
    base_score = nda_matches
    
    # Penalize if we find SOW indicators
    penalty = sow_matches * 0.5
    
    max(0, base_score - penalty)
  end

  defp calculate_sow_score(text) do
    sow_keywords = [
      "statement of work",
      "scope of work", 
      "deliverables",
      "milestones",
      "sow",
      "work order",
      "project scope",
      "project plan",
      "timeline",
      "deliverable",
      "milestone",
      "task",
      "assignment"
    ]
    
    nda_keywords = [
      "non-disclosure agreement",
      "confidentiality agreement",
      "nda", 
      "confidential information",
      "proprietary information",
      "trade secrets"
    ]
    
    sow_matches = count_keyword_matches(text, sow_keywords)
    nda_matches = count_keyword_matches(text, nda_keywords)
    
    # Boost SOW score if we find strong SOW indicators
    base_score = sow_matches
    
    # Penalize if we find NDA indicators
    penalty = nda_matches * 0.5
    
    max(0, base_score - penalty)
  end

  defp count_keyword_matches(text, keywords) do
    keywords
    |> Enum.map(fn keyword ->
      case String.contains?(text, keyword) do
        true -> 1
        false -> 0
      end
    end)
    |> Enum.sum()
  end
end
