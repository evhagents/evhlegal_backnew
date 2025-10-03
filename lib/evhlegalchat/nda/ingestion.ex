defmodule Evhlegalchat.Nda.Ingestion do
  @moduledoc """
  NDA document ingestion module for processing uploaded legal documents.
  Handles PDF text extraction, parsing, and storage in the database.
  """

  alias Evhlegalchat.Nda.{PdfParser, NdaAnatomy}
  alias Evhlegalchat.Repo

  require Logger

  @doc """
  Processes an uploaded document and creates an NDA anatomy record.

  ## Parameters
  - `entry`: Phoenix LiveView upload entry
  - `temp_path`: Temporary file path from upload
  - `attrs`: Additional attributes (optional)

  ## Returns
  - `{:ok, nda_anatomy}` on success
  - `{:error, reason}` on failure
  """
  def process_document(entry, temp_path, attrs \\ %{}) do
    with {:ok, raw_text} <- PdfParser.extract_from_upload(entry, temp_path),
         {:ok, parsed_data} <- parse_nda_content(raw_text),
         {:ok, nda_anatomy} <- create_nda_record(entry, raw_text, parsed_data, attrs) do
      Logger.info("Successfully processed NDA document: #{entry.client_name}")
      {:ok, nda_anatomy}
    else
      {:error, reason} = error ->
        Logger.error("Failed to process NDA document #{entry.client_name}: #{reason}")
        error
    end
  end

  @doc """
  Parses NDA content and extracts structured information.
  This is a basic implementation that can be enhanced with AI/ML parsing.
  """
  def parse_nda_content(raw_text) do
    parsed_data = %{
      "parties" => extract_parties(raw_text),
      "effective_date" => extract_effective_date(raw_text),
      "key_terms" => extract_key_terms(raw_text),
      "sections" => identify_sections(raw_text)
    }

    {:ok, parsed_data}
  end

  defp create_nda_record(entry, raw_text, parsed_data, attrs) do
    nda_attrs =
      attrs
      |> Map.merge(%{
        "original_name" => entry.client_name,
        "raw_text" => raw_text,
        "parsed_json" => parsed_data,
        "party_disclosing" => get_in(parsed_data, ["parties", "disclosing"]),
        "party_receiving" => get_in(parsed_data, ["parties", "receiving"]),
        "effective_date" => parse_date(get_in(parsed_data, ["effective_date"])),
        "definitions" => get_in(parsed_data, ["sections", "definitions"]),
        "confidential_information" =>
          get_in(parsed_data, ["sections", "confidential_information"]),
        "exclusions" => get_in(parsed_data, ["sections", "exclusions"]),
        "obligations" => get_in(parsed_data, ["sections", "obligations"]),
        "term" => get_in(parsed_data, ["sections", "term"]),
        "return_of_materials" => get_in(parsed_data, ["sections", "return_of_materials"]),
        "remedies" => get_in(parsed_data, ["sections", "remedies"]),
        "governing_law" => get_in(parsed_data, ["sections", "governing_law"]),
        "miscellaneous" => get_in(parsed_data, ["sections", "miscellaneous"])
      })

    %NdaAnatomy{}
    |> NdaAnatomy.changeset(nda_attrs)
    |> Repo.insert()
  end

  # Basic text parsing functions - these can be enhanced with more sophisticated NLP
  defp extract_parties(text) do
    # Simple regex-based party extraction
    disclosing = extract_pattern(text, ~r/disclos(?:ing|er)[\s\w]*?party[\s:]+([^,\n\.]+)/i)
    receiving = extract_pattern(text, ~r/receiv(?:ing|er)[\s\w]*?party[\s:]+([^,\n\.]+)/i)

    %{
      "disclosing" => disclosing,
      "receiving" => receiving
    }
  end

  defp extract_effective_date(text) do
    # Look for common date patterns
    date_patterns = [
      ~r/effective\s+date[\s:]+([^,\n\.]+)/i,
      ~r/dated\s+([^,\n\.]+)/i,
      ~r/(\d{1,2}\/\d{1,2}\/\d{4})/,
      ~r/(\w+\s+\d{1,2},\s+\d{4})/
    ]

    Enum.find_value(date_patterns, fn pattern ->
      extract_pattern(text, pattern)
    end)
  end

  defp extract_key_terms(text) do
    # Look for definition sections
    if String.contains?(String.downcase(text), "definition") do
      # This is a simplified extraction - can be enhanced
      definition_section = extract_section(text, "definition")
      parse_definitions(definition_section)
    else
      []
    end
  end

  defp identify_sections(text) do
    sections = %{}

    # Common NDA section patterns
    section_patterns = %{
      "definitions" =>
        ~r/(definitions?|defined terms?)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims,
      "confidential_information" =>
        ~r/(confidential information|proprietary information)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims,
      "exclusions" => ~r/(exclusions?|exceptions?)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims,
      "obligations" =>
        ~r/(obligations?|duties|responsibilities)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims,
      "term" => ~r/(term|duration|period)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims,
      "return_of_materials" =>
        ~r/(return|destruction|materials)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims,
      "remedies" =>
        ~r/(remedies?|damages?|injunctive relief)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims,
      "governing_law" =>
        ~r/(governing law|jurisdiction|applicable law)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims,
      "miscellaneous" =>
        ~r/(miscellaneous|general provisions?|other)(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims
    }

    Enum.reduce(section_patterns, sections, fn {key, pattern}, acc ->
      case Regex.run(pattern, text) do
        [_full_match, _header, content] -> Map.put(acc, key, String.trim(content))
        _ -> acc
      end
    end)
  end

  defp extract_pattern(text, pattern) do
    case Regex.run(pattern, text) do
      [_full_match, captured] -> String.trim(captured)
      _ -> nil
    end
  end

  defp extract_section(text, section_name) do
    pattern = ~r/#{section_name}(.*?)(?=\n\s*\d+\.|\n\s*[A-Z][^\.]*\.\s|\z)/ims

    case Regex.run(pattern, text) do
      [_full_match, content] -> String.trim(content)
      _ -> ""
    end
  end

  defp parse_definitions(definition_text) do
    # Simple definition parsing - can be enhanced
    definition_text
    |> String.split(~r/\n\s*/)
    |> Enum.filter(&(String.length(&1) > 10))
    # Limit to first 10 definitions
    |> Enum.take(10)
  end

  defp parse_date(nil), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    # Try to parse common date formats
    case Date.from_iso8601(date_string) do
      {:ok, date} ->
        date

      _ ->
        # Try other formats if needed
        nil
    end
  end

  defp parse_date(_), do: nil
end
