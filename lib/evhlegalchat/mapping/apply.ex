defmodule Evhlegalchat.Mapping.Apply do
  @moduledoc """
  Generic appliers for agreements and SOW/NDA subsets.
  """
  import Ecto.Query
  alias Ecto.Multi
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Mapping.{ExtractedFact, FieldAudit}
  alias Evhlegalchat.{Agreement}
  alias Evhlegalchat.NDA.KeyClause
  alias Evhlegalchat.SOW.{Deliverable, Milestone, PricingSchedule, RateCard, InvoicingTerm}

  def apply_fact(%ExtractedFact{} = fact) do
    case {fact.target_table, fact.target_column} do
      {"agreements", col} -> apply_agreement_field(fact, col)
      {"nda_key_clauses", _} -> apply_nda_key(fact)
      {"sow_deliverables", _} -> apply_sow_deliverable(fact)
      {"sow_milestones", _} -> apply_sow_milestone(fact)
      {"sow_pricing_schedules", _} -> apply_sow_pricing(fact)
      {"sow_rate_cards", _} -> apply_sow_rate_card(fact)
      {"sow_invoicing_terms", _} -> apply_sow_invoicing(fact)
      _ -> {:error, :unsupported_target}
    end
  end

  defp apply_agreement_field(fact, column) do
    agreement_id = fact.target_pk_value
    current = Repo.get(Agreement, agreement_id)
    old_value = Map.get(current, String.to_atom(column))
    new_value = value_for_fact(fact, column)
    if old_value == new_value do
      {:ok, current}
    else
      Multi.new()
      |> Multi.update(:update, Agreement.changeset(current, %{column => new_value}))
      |> Multi.insert(:audit, FieldAudit.changeset(%FieldAudit{}, %{
        agreement_id: fact.agreement_id,
        target_table: fact.target_table,
        target_pk_name: fact.target_pk_name,
        target_pk_value: fact.target_pk_value,
        target_column: fact.target_column,
        old_value: encode_scalar(old_value),
        new_value: encode_scalar(new_value),
        fact_id: fact.fact_id,
        actor_user_id: nil,
        action: "apply",
        created_at: DateTime.utc_now()
      }))
      |> Multi.update(:fact, ExtractedFact.changeset(fact, %{status: :applied}))
      |> Repo.transaction()
    end
  end

  defp apply_nda_key(%ExtractedFact{} = fact) do
    key = fact.target_column |> String.to_existing_atom()
    attrs = %{
      agreement_id: fact.agreement_id,
      key: key,
      value_text: fact.normalized_value || fact.raw_value,
      value_numeric: fact.normalized_numeric,
      value_unit: fact.normalized_unit,
      evidence_clause_id: fact.evidence_clause_id,
      confidence: fact.confidence,
      ingest_timestamp: get_agreement_field(fact.agreement_id, :ingest_timestamp),
      extractor_version: get_agreement_field(fact.agreement_id, :extractor_version),
      model_versions: get_agreement_field(fact.agreement_id, :model_versions)
    }

    cs = KeyClause.changeset(%KeyClause{}, attrs)

    Multi.new()
    |> Multi.insert(:upsert, cs,
      on_conflict: [set: [value_text: attrs.value_text, value_numeric: attrs.value_numeric, value_unit: attrs.value_unit, evidence_clause_id: attrs.evidence_clause_id, confidence: attrs.confidence]],
      conflict_target: [:agreement_id, :key]
    )
    |> Multi.insert(:audit, FieldAudit.changeset(%FieldAudit{}, %{
      agreement_id: fact.agreement_id,
      target_table: fact.target_table,
      target_pk_name: fact.target_pk_name,
      target_pk_value: fact.target_pk_value,
      target_column: fact.target_column,
      old_value: nil,
      new_value: fact.normalized_value || fact.raw_value,
      fact_id: fact.fact_id,
      actor_user_id: nil,
      action: "apply",
      created_at: DateTime.utc_now()
    }))
    |> Multi.update(:fact, ExtractedFact.changeset(fact, %{status: :applied}))
    |> Repo.transaction()
  end

  defp apply_sow_deliverable(%ExtractedFact{} = fact) do
    with id when is_integer(id) <- fact.target_pk_value,
         %Deliverable{} = current <- Repo.get(Deliverable, id),
         {:ok, field, value} <- map_deliverable_field_value(fact) do
      update_row_with_audit(current, fact, field, value)
    else
      nil -> {:error, :target_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_target}
    end
  end

  defp apply_sow_milestone(%ExtractedFact{} = fact) do
    with id when is_integer(id) <- fact.target_pk_value,
         %Milestone{} = current <- Repo.get(Milestone, id),
         {:ok, field, value} <- map_milestone_field_value(fact) do
      update_row_with_audit(current, fact, field, value)
    else
      nil -> {:error, :target_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_target}
    end
  end

  defp apply_sow_pricing(%ExtractedFact{} = fact) do
    with id when is_integer(id) <- fact.target_pk_value,
         %PricingSchedule{} = current <- Repo.get(PricingSchedule, id),
         {:ok, field, value} <- map_pricing_field_value(fact) do
      update_row_with_audit(current, fact, field, value)
    else
      nil -> {:error, :target_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_target}
    end
  end

  defp apply_sow_rate_card(%ExtractedFact{} = fact) do
    with id when is_integer(id) <- fact.target_pk_value,
         %RateCard{} = current <- Repo.get(RateCard, id),
         {:ok, field, value} <- map_rate_card_field_value(fact) do
      update_row_with_audit(current, fact, field, value)
    else
      nil -> {:error, :target_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_target}
    end
  end

  defp apply_sow_invoicing(%ExtractedFact{} = fact) do
    with id when is_integer(id) <- fact.target_pk_value,
         %InvoicingTerm{} = current <- Repo.get(InvoicingTerm, id),
         {:ok, field, value} <- map_invoicing_field_value(fact) do
      update_row_with_audit(current, fact, field, value)
    else
      nil -> {:error, :target_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_target}
    end
  end

  defp value_for_fact(fact, column) do
    case column do
      "effective_date" -> parse_date(fact)
      "term_length_months" -> as_integer(fact)
      "early_termination_allowed" -> to_bool(fact)
      "survival_period_months" -> as_integer(fact)
      _ -> fact.normalized_value || fact.raw_value
    end
  end

  defp parse_date(fact) do
    with %Date{} = date <- cast_date(fact.normalized_value || fact.raw_value) do
      date
    else
      _ -> nil
    end
  end

  defp cast_date(nil), do: nil
  defp cast_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  defp as_integer(%{normalized_numeric: %Decimal{} = d}), do: Decimal.to_integer(d)
  defp as_integer(%{normalized_numeric: n}) when is_integer(n), do: n
  defp as_integer(%{normalized_value: v}) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> nil
    end
  end
  defp as_integer(_), do: nil

  defp to_bool(%{normalized_value: v}) when v in ["true", "false"], do: v == "true"
  defp to_bool(%{raw_value: v}) when is_binary(v), do: String.contains?(String.downcase(v), "allow")
  defp to_bool(_), do: nil

  defp encode_scalar(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_scalar(v) when is_binary(v) or is_nil(v), do: v
  defp encode_scalar(v) when is_integer(v), do: Integer.to_string(v)
  defp encode_scalar(%Decimal{} = d), do: Decimal.to_string(d)
  defp encode_scalar(v), do: to_string(v)

  defp get_agreement_field(agreement_id, field) do
    case Repo.get(Agreement, agreement_id) do
      nil -> nil
      ag -> Map.get(ag, field)
    end
  end

  # Generic row update with audit + fact status
  defp update_row_with_audit(current, %ExtractedFact{} = fact, field, value) when is_atom(field) do
    old_value = Map.get(current, field)
    if old_value == value do
      {:ok, current}
    else
      changes = Map.put(%{}, field, value)
      Multi.new()
      |> Multi.update(:update, current.__struct__.changeset(current, changes))
      |> Multi.insert(:audit, FieldAudit.changeset(%FieldAudit{}, %{
        agreement_id: fact.agreement_id,
        target_table: fact.target_table,
        target_pk_name: fact.target_pk_name,
        target_pk_value: fact.target_pk_value,
        target_column: fact.target_column,
        old_value: encode_scalar(old_value),
        new_value: encode_scalar(value),
        fact_id: fact.fact_id,
        actor_user_id: nil,
        action: "apply",
        created_at: DateTime.utc_now()
      }))
      |> Multi.update(:fact, ExtractedFact.changeset(fact, %{status: :applied}))
      |> Repo.transaction()
    end
  end

  # Field mapping helpers for SOW modules
  defp map_deliverable_field_value(%ExtractedFact{target_column: col} = fact) do
    case col do
      "title" -> {:ok, :title, fact.normalized_value || fact.raw_value}
      "description" -> {:ok, :description, fact.normalized_value || fact.raw_value}
      "artifact_type" -> {:ok, :artifact_type, fact.normalized_value || fact.raw_value}
      "due_date" -> {:ok, :due_date, parse_date(fact)}
      "acceptance_notes" -> {:ok, :acceptance_notes, fact.normalized_value || fact.raw_value}
      _ -> {:error, :unsupported_column}
    end
  end

  defp map_milestone_field_value(%ExtractedFact{target_column: col} = fact) do
    case col do
      "title" -> {:ok, :title, fact.normalized_value || fact.raw_value}
      "description" -> {:ok, :description, fact.normalized_value || fact.raw_value}
      "target_date" -> {:ok, :target_date, parse_date(fact)}
      "depends_on" -> {:ok, :depends_on, to_integer(fact)}
      _ -> {:error, :unsupported_column}
    end
  end

  defp map_pricing_field_value(%ExtractedFact{target_column: col} = fact) do
    case col do
      "pricing_model" -> {:ok, :pricing_model, to_enum_value(PricingSchedule, :pricing_model, fact)}
      "currency" -> {:ok, :currency, fact.normalized_value || fact.raw_value}
      "fixed_total" -> {:ok, :fixed_total, to_decimal(fact)}
      "not_to_exceed_total" -> {:ok, :not_to_exceed_total, to_decimal(fact)}
      "usage_unit" -> {:ok, :usage_unit, fact.normalized_value || fact.raw_value}
      "usage_rate" -> {:ok, :usage_rate, to_decimal(fact)}
      "notes" -> {:ok, :notes, fact.normalized_value || fact.raw_value}
      _ -> {:error, :unsupported_column}
    end
  end

  defp map_rate_card_field_value(%ExtractedFact{target_column: col} = fact) do
    case col do
      "role" -> {:ok, :role, fact.normalized_value || fact.raw_value}
      "hourly_rate" -> {:ok, :hourly_rate, to_decimal(fact)}
      "currency" -> {:ok, :currency, fact.normalized_value || fact.raw_value}
      "effective_start" -> {:ok, :effective_start, parse_date(fact)}
      "effective_end" -> {:ok, :effective_end, parse_date(fact)}
      _ -> {:error, :unsupported_column}
    end
  end

  defp map_invoicing_field_value(%ExtractedFact{target_column: col} = fact) do
    case col do
      "billing_trigger" -> {:ok, :billing_trigger, to_enum_value(InvoicingTerm, :billing_trigger, fact)}
      "frequency" -> {:ok, :frequency, fact.normalized_value || fact.raw_value}
      "net_terms_days" -> {:ok, :net_terms_days, to_integer(fact)}
      "late_fee_percent" -> {:ok, :late_fee_percent, to_decimal(fact)}
      "invoice_notes" -> {:ok, :invoice_notes, fact.normalized_value || fact.raw_value}
      _ -> {:error, :unsupported_column}
    end
  end

  defp to_integer(%{normalized_numeric: %Decimal{} = d}), do: Decimal.to_integer(d)
  defp to_integer(%{normalized_numeric: n}) when is_integer(n), do: n
  defp to_integer(%{normalized_value: v}) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      _ -> nil
    end
  end
  defp to_integer(_), do: nil

  defp to_decimal(%{normalized_numeric: %Decimal{} = d}), do: d
  defp to_decimal(%{normalized_numeric: n}) when is_number(n), do: Decimal.new(n)
  defp to_decimal(%{normalized_value: v}) when is_binary(v) do
    case Decimal.parse(v) do
      {:ok, d} -> d
      _ -> nil
    end
  end
  defp to_decimal(_), do: nil

  defp to_enum_value(module, field, %{normalized_value: v}) when is_binary(v) do
    # Let Ecto changeset cast validate the enum later; pass raw string/atom
    try do
      String.to_existing_atom(v)
    rescue
      _ -> v
    end
  end
  defp to_enum_value(_module, _field, _), do: nil
end



