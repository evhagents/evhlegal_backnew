defmodule Evhlegalchat.Promotion.Title do
  @moduledoc """
  Title derivation for legal documents.
  
  Extracts or generates appropriate titles for agreements
  based on clause headings and filenames.
  """

  @doc """
  Derives a title from clauses and filename.
  
  Returns {:ok, title} if derived from content, {:fallback, title} if from filename.
  """
  def derive(clauses, filename) when is_list(clauses) and is_binary(filename) do
    # Try to extract title from clause headings first
    case extract_title_from_clauses(clauses) do
      {:ok, title} -> {:ok, title}
      :not_found -> {:fallback, derive_from_filename(filename)}
    end
  end

  # Private functions

  defp extract_title_from_clauses(clauses) do
    # Look for the first substantial heading (5-100 chars, not just numbers)
    clauses
    |> Enum.find(fn clause ->
      heading = clause.heading_text
      heading && 
      String.length(heading) >= 5 && 
      String.length(heading) <= 100 &&
      not String.match?(heading, ~r/^\d+\.?\s*$/) # Not just a number
    end)
    |> case do
      nil -> :not_found
      clause -> {:ok, clean_title(clause.heading_text)}
    end
  end

  defp derive_from_filename(filename) do
    filename
    |> Path.basename()
    |> Path.rootname()
    |> clean_filename()
  end

  defp clean_title(title) do
    title
    |> String.trim()
    |> String.replace(~r/\s+/, " ") # Normalize whitespace
    |> String.replace(~r/^[\d\.\s]+/, "") # Remove leading numbers/punctuation
    |> String.trim()
  end

  defp clean_filename(filename) do
    filename
    |> String.replace(~r/[-_]/g, " ") # Replace separators with spaces
    |> String.replace(~r/\s+/, " ") # Normalize whitespace
    |> String.trim()
    |> case do
      "" -> "Untitled Document"
      cleaned -> cleaned
    end
  end
end
