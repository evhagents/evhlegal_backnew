defmodule Evhlegalchat.Enrich.SOW do
  @moduledoc """
  SOW enrichment orchestrator with conservative extractors.
  """
  import Ecto.Query
  alias Evhlegalchat.Repo
  alias Evhlegalchat.SOW.{Deliverable, Milestone, PricingSchedule, RateCard, InvoicingTerm, ExpensesPolicy, Assumption}

  def run(agreement_id) do
    clauses = load_clauses(agreement_id)
    deliverables = extract_deliverables(clauses)
    milestones = extract_milestones(clauses)
    pricing = extract_pricing(clauses)
    rate_cards = extract_rate_cards(clauses)
    invoicing = extract_invoicing(clauses)
    expenses = extract_expenses(clauses)
    assumptions = extract_assumptions(clauses)

    deliverables_count = upsert_deliverables(agreement_id, deliverables)
    milestones_count = upsert_milestones(agreement_id, milestones)
    pricing_count = upsert_pricing(agreement_id, pricing)
    rate_cards_count = upsert_rate_cards(agreement_id, rate_cards)
    invoicing_count = upsert_invoicing(agreement_id, invoicing)
    expenses_count = upsert_expenses(agreement_id, expenses)
    assumptions_count = upsert_assumptions(agreement_id, assumptions)

    %{deliverables: deliverables_count, milestones: milestones_count, pricing: pricing_count, rate_cards: rate_cards_count, invoicing: invoicing_count, expenses: expenses_count, assumptions: assumptions_count}
  end

  defp load_clauses(agreement_id) do
    from(c in "clauses", where: c.agreement_id == ^agreement_id, select: %{clause_id: c.clause_id, heading_text: c.heading_text, text_snippet: c.text_snippet})
    |> Repo.all()
  end

  defp extract_deliverables(clauses) do
    # Find deliverables/scope headings and collect bullet items as titles
    candidates = Enum.filter(clauses, fn c -> String.match?(c.heading_text || "", ~r/^(deliverables?|scope of work)/i) end)
    candidates
    |> Enum.flat_map(fn c ->
      bullets = Regex.scan(~r/^[-•]\s+(.+)$/m, c.text_snippet || "")
      Enum.map(bullets, fn [_, title] -> %{title: String.trim(title), description: nil, artifact_type: nil, due_date: nil, acceptance_notes: nil} end)
    end)
    |> Enum.uniq_by(& &1.title)
    |> Enum.take(200)
  end

  defp extract_milestones(clauses) do
    candidates = Enum.filter(clauses, fn c -> String.match?(c.heading_text || "", ~r/^milestones?/i) end)
    candidates
    |> Enum.flat_map(fn c ->
      bullets = Regex.scan(~r/^[-•]\s+(.+)$/m, c.text_snippet || "")
      Enum.map(bullets, fn [_, line] ->
        {title, date} = parse_title_date(line)
        %{title: title, description: nil, target_date: date, depends_on: nil}
      end)
    end)
    |> Enum.uniq_by(& &1.title)
    |> Enum.take(200)
  end

  defp extract_pricing(clauses) do
    text = concat(clauses)
    [
      {~r/(?i)fixed fee|fixed-price|lump sum/, :fixed_fee},
      {~r/(?i)not to exceed|NTE\b/, :not_to_exceed},
      {~r/(?i)time\s*&\s*materials|t\s*&\s*m|hourly/, :t_and_m},
      {~r/(?i)usage[- ]based|per\s+use/, :usage_based}
    ]
    |> Enum.reduce([], fn {re, model}, acc ->
      if Regex.match?(re, text), do: [%{pricing_model: model} | acc], else: acc
    end)
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp extract_rate_cards(clauses) do
    text = concat(clauses)
    Regex.scan(~r/(?i)(?:role|title):?\s*([A-Za-z \/-]+)\s*[,;–-]\s*\$?(\d+(?:\.\d{2})?)\s*\/\s*(?:hour|hr)/, text)
    |> Enum.map(fn [_, role, rate] -> %{role: String.trim(role), hourly_rate: Decimal.new(rate), currency: "USD", effective_start: Date.utc_today(), effective_end: nil} end)
    |> Enum.uniq_by(& &1.role)
    |> Enum.take(50)
  end

  defp extract_invoicing(clauses) do
    text = concat(clauses)
    base = []
    base = if Regex.match?(~r/(?i)monthly|each month/, text), do: [%{billing_trigger: :calendar, frequency: "monthly"} | base], else: base
    base = if Regex.match?(~r/(?i)on acceptance/, text), do: [%{billing_trigger: :on_acceptance} | base], else: base
    base = if Regex.match?(~r/(?i)on completion/, text), do: [%{billing_trigger: :completion} | base], else: base
    base = if Regex.match?(~r/(?i)milestone/, text), do: [%{billing_trigger: :milestone} | base], else: base
    base
    |> Enum.uniq_by(& &1.billing_trigger)
    |> Enum.take(5)
  end

  defp extract_expenses(clauses) do
    text = concat(clauses)
    reimbursable = Regex.match?(~r/(?i)reimbursable|reimbursed/, text)
    non_reimbursable = Regex.scan(~r/(?i)non[- ]reimbursable[:\s]+(.+?)(?:\.|\n)/, text)
    |> Enum.map(fn [_, t] -> t end)
    |> Enum.join("; ")
    [%{reimbursable: reimbursable, preapproval_required: Regex.match?(~r/(?i)pre[- ]approval required|prior approval/, text), caps_notes: nil, non_reimbursable: (if non_reimbursable == "", do: nil, else: non_reimbursable)}]
  end

  defp extract_assumptions(clauses) do
    candidates = Enum.filter(clauses, fn c -> String.match?(c.heading_text || "", ~r/^(assumptions?|dependencies)/i) end)
    candidates
    |> Enum.flat_map(fn c ->
      bullets = Regex.scan(~r/^[-•]\s+(.+)$/m, c.text_snippet || "")
      Enum.map(bullets, fn [_, t] -> %{category: nil, text: String.trim(t), risk_if_breached: nil} end)
    end)
    |> Enum.uniq_by(& &1.text)
    |> Enum.take(200)
  end

  defp upsert_deliverables(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      cs = Deliverable.changeset(%Deliverable{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(cs,
             on_conflict: [set: [description: attrs[:description], artifact_type: attrs[:artifact_type], due_date: attrs[:due_date], acceptance_notes: attrs[:acceptance_notes]]],
             conflict_target: [:agreement_id, :title]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_milestones(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      cs = Milestone.changeset(%Milestone{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(cs,
             on_conflict: [set: [description: attrs[:description], target_date: attrs[:target_date], depends_on: attrs[:depends_on]]],
             conflict_target: [:agreement_id, :title]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_pricing(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      cs = PricingSchedule.changeset(%PricingSchedule{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(cs,
             on_conflict: [set: [currency: attrs[:currency] || "USD", fixed_total: attrs[:fixed_total], not_to_exceed_total: attrs[:not_to_exceed_total], usage_unit: attrs[:usage_unit], usage_rate: attrs[:usage_rate], notes: attrs[:notes]]],
             conflict_target: [:agreement_id, :pricing_model]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_rate_cards(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      cs = RateCard.changeset(%RateCard{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(cs,
             on_conflict: [set: [hourly_rate: attrs[:hourly_rate], currency: attrs[:currency] || "USD", effective_end: attrs[:effective_end]]],
             conflict_target: [:agreement_id, :role, :effective_start]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_invoicing(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      cs = InvoicingTerm.changeset(%InvoicingTerm{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(cs,
             on_conflict: [set: [frequency: attrs[:frequency], net_terms_days: attrs[:net_terms_days], late_fee_percent: attrs[:late_fee_percent], invoice_notes: attrs[:invoice_notes]]],
             conflict_target: [:agreement_id, :billing_trigger]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_expenses(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      cs = ExpensesPolicy.changeset(%ExpensesPolicy{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(cs,
             on_conflict: [set: [reimbursable: attrs[:reimbursable], preapproval_required: attrs[:preapproval_required], caps_notes: attrs[:caps_notes], non_reimbursable: attrs[:non_reimbursable]]],
             conflict_target: [:agreement_id]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp upsert_assumptions(agreement_id, items) do
    Enum.reduce(items, 0, fn attrs, acc ->
      cs = Assumption.changeset(%Assumption{}, Map.put(attrs, :agreement_id, agreement_id))
      case Repo.insert(cs,
             on_conflict: [set: [category: attrs[:category], risk_if_breached: attrs[:risk_if_breached]]],
             conflict_target: [:agreement_id, :text]
           ) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp parse_title_date(line) do
    t = String.trim(line)
    cond do
      Regex.match?(~r/\b\d{4}-\d{2}-\d{2}\b/, t) ->
        [date_str] = Regex.run(~r/\b\d{4}-\d{2}-\d{2}\b/, t)
        title = String.trim(String.replace(t, date_str, ""))
        case Date.from_iso8601(date_str) do
          {:ok, d} -> {title, d}
          _ -> {title, nil}
        end
      true -> {t, nil}
    end
  end

  defp concat(clauses), do: Enum.map(clauses, &(&1.text_snippet || "")) |> Enum.join("\n\n")
end


