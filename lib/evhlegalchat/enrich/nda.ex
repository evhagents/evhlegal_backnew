defmodule Evhlegalchat.Enrich.NDA do
  @moduledoc """
  NDA enrichment orchestrator and pure extractors entrypoints.
  """
  require Logger
  import Ecto.Query
  alias Evhlegalchat.Repo
  alias Evhlegalchat.NDA.{Party, Carveout, KeyClause, Signature}
  alias Evhlegalchat.Agreement
  alias Evhlegalchat.Review

  @min_conf_numeric 0.6

  def run(agreement_id) do
    clauses = load_clauses(agreement_id)
    agreement = Repo.get(Agreement, agreement_id)
    if clauses == [] do
      {empty_counts(), false}
    else
      {parties, party_flags} = extract_parties(clauses)
      {keys, key_flags} = extract_keys(clauses, agreement)
      {carveouts, carve_flags} = extract_carveouts(clauses)
      {signatures, sig_flags} = extract_signatures(clauses)

      {saved_counts, flagged?} = Repo.transaction(fn ->
        counts = %{
          parties: upsert_parties(agreement_id, parties),
          key_clauses: upsert_keys(agreement_id, keys),
          carveouts: upsert_carveouts(agreement_id, carveouts),
          signatures: upsert_signatures(agreement_id, signatures)
        }

        flags = party_flags ++ key_flags ++ carve_flags ++ sig_flags
        Enum.each(flags, fn {entity, reason, evidence_clause_id, details} ->
          Review.flag!(agreement_id, entity, reason, evidence_clause_id, details)
        end)

        {counts, flags != []}
      end)

      {saved_counts, flagged?}
    end
  end

  defp empty_counts, do: %{parties: 0, key_clauses: 0, carveouts: 0, signatures: 0}

  defp load_clauses(agreement_id) do
    from(c in "clauses", where: c.agreement_id == ^agreement_id, select: %{clause_id: c.clause_id, heading_text: c.heading_text, text_snippet: c.text_snippet})
    |> Repo.all()
  end

  # --- Extractors (conservative regex-based) ---

  defp extract_parties(clauses) do
    text = concatenate(clauses)
    # Capture candidate names following party cues
    name_matches = Regex.scan(~r/(?:Company|Party|Disclos(?:ing|er)|Receiv(?:ing|er))[:\s]+([A-Z][A-Za-z0-9 .,'&\-\/]{2,255})/, text)

    parties =
      name_matches
      |> Enum.map(fn [_, raw_name] ->
        name = String.trim(raw_name)
        clause_id = nearest_clause_id(clauses, name)
        snippet = clause_text_by_id(clauses, clause_id)
        role = infer_role(snippet)
        %{role: role, display_name: name, evidence_clause_id: clause_id}
      end)
      |> Enum.uniq_by(fn %{display_name: n, evidence_clause_id: cid} -> {String.downcase(n), cid} end)

    flags = if length(parties) < 2, do: [{:parties, :insufficient_parties, nil, %{found: length(parties)}}], else: []
    {parties, flags}
  end

  defp extract_keys(clauses, agreement) do
    text = concatenate(clauses)
    min_conf = min_conf_numeric()

    # term duration
    term =
      case Regex.run(~r/(?i)(term|duration).{0,50}?(\d+)\s*(year|month)/, text) do
        [_, _, num, unit] ->
          numeric = String.to_integer(num)
          months = if String.match?(unit, ~r/^year/i), do: numeric * 12, else: numeric
          confidence = 0.8
          attrs = %{key: :term_duration, value_text: "#{numeric} #{unit}", evidence_clause_id: nearest_clause_id(clauses, num), confidence: confidence}
          attrs = gate_numeric(attrs, confidence, months, "months", min_conf)
          [attrs]
        _ -> []
      end

    # governing law: prefer agreement.governing_law, else detect in text
    gov_law =
      cond do
        agreement && is_binary(agreement.governing_law) && String.trim(agreement.governing_law) != "" ->
          [%{key: :governing_law, value_text: agreement.governing_law, evidence_clause_id: nil, confidence: 0.9}]
        true ->
          case Regex.run(~r/(?i)governed by the laws of\s+([A-Za-z .,'\-]+?)(?:\.|\n|$)/, text) do
            [_, law] -> [%{key: :governing_law, value_text: String.trim(law), evidence_clause_id: nearest_clause_id(clauses, law), confidence: 0.7}]
            _ -> []
          end
      end

    keys = term ++ gov_law
    flags = if Enum.find(term, &(&1.key == :term_duration)) == nil, do: [{:key_clauses, :missing_term_duration, nil, %{}}], else: []
    {keys, flags}
  end

  defp extract_carveouts(clauses) do
    # Prefer clauses with exclusion headings, but also scan for classic patterns
    heading_candidates = Enum.filter(clauses, fn c -> String.match?(c.heading_text || "", ~r/Exclusions|Exceptions/i) end)
    from_headings =
      heading_candidates
      |> Enum.flat_map(fn c ->
        bullets = Regex.scan(~r/^[-•]\s+(.+)$/m, c.text_snippet || "")
        Enum.map(bullets, fn [_, t] -> %{label: nil, text: String.trim(t), confidence: 0.7, evidence_clause_id: c.clause_id} end)
      end)

    pattern_candidates =
      clauses
      |> Enum.flat_map(fn c ->
        Regex.scan(~r/(?i)(?:does not include|shall not include|except that)[:\s]+(.+?)(?:\n|\.)/, c.text_snippet || "")
        |> Enum.map(fn [_, t] -> %{label: nil, text: String.trim(t), confidence: 0.6, evidence_clause_id: c.clause_id} end)
      end)

    {from_headings ++ pattern_candidates, []}
  end

  defp extract_signatures(clauses) do
    sigs =
      clauses
      |> Enum.filter(fn c -> String.match?(c.heading_text || "", ~r/(IN WITNESS WHEREOF|SIGNATURES?)/i) end)
      |> Enum.flat_map(fn c ->
        Regex.scan(~r/\b([A-Z][A-Za-z .'-]{1,100}),\s*([A-Za-z .'-]{1,100})\s*(?:dated|on)?\s*(\w+\s+\d{1,2},\s+\d{4})?/, c.text_snippet || "")
        |> Enum.map(fn [_, name, title, date] -> %{signer_name: name, signer_title: title, signed_date: parse_date(date), evidence_clause_id: c.clause_id, confidence: 0.7} end)
      end)
    {sigs, []}
  end

  defp upsert_parties(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      changeset = Party.changeset(%Party{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(changeset,
             on_conflict: [set: [legal_name_norm: attrs[:legal_name_norm]]],
             conflict_target: [:agreement_id, :display_name, :evidence_clause_id]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_keys(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      changeset = KeyClause.changeset(%KeyClause{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(changeset,
             on_conflict: [set: [value_text: attrs[:value_text], value_numeric: attrs[:value_numeric], value_unit: attrs[:value_unit], confidence: attrs[:confidence]]],
             conflict_target: [:agreement_id, :key]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_carveouts(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      changeset = Carveout.changeset(%Carveout{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:agreement_id, :text, :evidence_clause_id]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_signatures(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      changeset = Signature.changeset(%Signature{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(changeset,
             on_conflict: [set: [signer_title: attrs[:signer_title], signed_date: attrs[:signed_date], confidence: attrs[:confidence]]],
             conflict_target: [:agreement_id, :signer_name, :signer_title, :signed_date, :evidence_clause_id]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp concatenate(clauses) do
    Enum.map(clauses, &(&1.text_snippet || "")) |> Enum.join("\n\n")
  end

  defp nearest_clause_id(clauses, snippet) do
    Enum.find_value(clauses, fn c -> if c.text_snippet && String.contains?(c.text_snippet, snippet), do: c.clause_id, else: nil end)
  end

  defp clause_text_by_id(clauses, nil), do: nil
  defp clause_text_by_id(clauses, id) do
    case Enum.find(clauses, &(&1.clause_id == id)) do
      nil -> nil
      c -> c.text_snippet || ""
    end
  end

  defp infer_role(nil), do: "other"
  defp infer_role(snippet) do
    s = String.downcase(snippet)
    cond do
      String.contains?(s, "disclosing party") -> "disclosing"
      String.contains?(s, "receiving party") -> "receiving"
      true -> "mutual"
    end
  end

  defp min_conf_numeric do
    get_in(Application.get_env(:evhlegalchat, Evhlegalchat.Enrich, []), [:nda, :min_confidence_numeric]) || 0.6
  end

  defp gate_numeric(attrs, confidence, numeric, unit, min_conf) do
    if confidence >= min_conf do
      Map.merge(attrs, %{value_numeric: numeric, value_unit: unit})
    else
      attrs
    end
  end

  defp parse_date(nil), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end
end


