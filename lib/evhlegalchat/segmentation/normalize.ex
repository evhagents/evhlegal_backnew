defmodule Evhlegalchat.Segmentation.Normalize do
  @moduledoc """
  Number label normalization utilities.
  
  Provides functions to normalize and standardize number labels
  from various formats (decimal, roman, alpha) to a consistent format.
  """

  @roman_numerals %{
    "I" => 1, "II" => 2, "III" => 3, "IV" => 4, "V" => 5,
    "VI" => 6, "VII" => 7, "VIII" => 8, "IX" => 9, "X" => 10,
    "XI" => 11, "XII" => 12, "XIII" => 13, "XIV" => 14, "XV" => 15,
    "XVI" => 16, "XVII" => 17, "XVIII" => 18, "XIX" => 19, "XX" => 20
  }

  @doc """
  Normalizes a number label to a consistent decimal format.
  
  Examples:
  - "1." -> "1"
  - "2.1" -> "2.1" 
  - "I." -> "1"
  - "II." -> "2"
  - "a)" -> "a"
  - "7(a)" -> "7.a"
  """
  def normalize_number_label(number_label) when is_binary(number_label) do
    number_label
    |> String.trim()
    |> normalize_roman_numerals()
    |> normalize_punctuation()
    |> normalize_parenthetical()
    |> normalize_alpha_sequences()
  end

  @doc """
  Extracts the numeric value from a number label.
  
  Returns the numeric representation for ordering purposes.
  """
  def extract_numeric_value(number_label) when is_binary(number_label) do
    case parse_number_label(number_label) do
      {:decimal, parts} ->
        # Convert decimal parts to numeric value
        parts
        |> Enum.map(&String.to_integer/1)
        |> decimal_to_numeric()
      
      {:roman, roman_str} ->
        # Convert roman numeral to numeric value
        Map.get(@roman_numerals, roman_str, 0)
      
      {:alpha, alpha_str} ->
        # Convert alpha sequence to numeric value
        alpha_to_numeric(alpha_str)
      
      :unknown ->
        0
    end
  end

  @doc """
  Validates that a number label follows expected patterns.
  
  Returns true if the label is valid, false otherwise.
  """
  def valid_number_label?(number_label) when is_binary(number_label) do
    case parse_number_label(number_label) do
      {:decimal, _} -> true
      {:roman, roman_str} -> Map.has_key?(@roman_numerals, roman_str)
      {:alpha, _} -> true
      :unknown -> false
    end
  end

  @doc """
  Compares two number labels for ordering.
  
  Returns :lt, :eq, or :gt based on the comparison.
  """
  def compare_number_labels(label1, label2) when is_binary(label1) and is_binary(label2) do
    val1 = extract_numeric_value(label1)
    val2 = extract_numeric_value(label2)
    
    cond do
      val1 < val2 -> :lt
      val1 > val2 -> :gt
      true -> :eq
    end
  end

  @doc """
  Generates a normalized snippet for display purposes.
  
  Creates a short, clean representation of the number label.
  """
  def generate_snippet(number_label) when is_binary(number_label) do
    normalized = normalize_number_label(number_label)
    
    # Truncate if too long
    if String.length(normalized) > 20 do
      String.slice(normalized, 0, 17) <> "..."
    else
      normalized
    end
  end

  # Private functions

  defp normalize_roman_numerals(label) do
    # Convert roman numerals to decimal
    roman_pattern = ~r/^([IVXLCM]+)\.?$/
    
    case Regex.run(roman_pattern, String.upcase(label)) do
      [_, roman_str] ->
        case Map.get(@roman_numerals, roman_str) do
          nil -> label  # Keep original if not recognized
          decimal -> to_string(decimal)
        end
      _ ->
        label
    end
  end

  defp normalize_punctuation(label) do
    # Remove trailing punctuation
    String.replace(label, ~r/[\.\)\]\s*$/, "")
  end

  defp normalize_parenthetical(label) do
    # Convert parenthetical notation to decimal
    # "7(a)" -> "7.a"
    String.replace(label, ~r/^(\d+)\(([a-z]+)\)$/, "\\1.\\2")
  end

  defp normalize_alpha_sequences(label) do
    # Ensure alpha sequences are lowercase
    String.downcase(label)
  end

  defp parse_number_label(label) do
    cond do
      # Decimal pattern: "1", "2.1", "3.2.1"
      Regex.match?(~r/^\d+(\.\d+)*$/, label) ->
        parts = String.split(label, ".")
        {:decimal, parts}
      
      # Roman pattern: "I", "II", "III"
      Regex.match?(~r/^[IVXLCM]+$/, String.upcase(label)) ->
        {:roman, String.upcase(label)}
      
      # Alpha pattern: "a", "b", "aa"
      Regex.match?(~r/^[a-z]+$/, label) ->
        {:alpha, label}
      
      true ->
        :unknown
    end
  end

  defp decimal_to_numeric(parts) do
    # Convert decimal parts to a single numeric value
    # "2.1" -> 2.1, "3.2.1" -> 3.21
    parts
    |> Enum.with_index()
    |> Enum.reduce(0, fn {part, index}, acc ->
      value = String.to_integer(part)
      multiplier = :math.pow(10, -index)
      acc + value * multiplier
    end)
  end

  defp alpha_to_numeric(alpha_str) do
    # Convert alpha sequence to numeric value
    # "a" -> 1, "b" -> 2, "aa" -> 27, etc.
    alpha_str
    |> String.to_charlist()
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.reduce(0, fn {char, index}, acc ->
      char_value = char - ?a + 1
      multiplier = :math.pow(26, index)
      acc + char_value * multiplier
    end)
    |> round()
  end
end