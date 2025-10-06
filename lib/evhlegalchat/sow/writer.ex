defmodule Evhlegalchat.SOW.Writer do
  @moduledoc """
  Atomically creates an agreement and all SOW child rows.

  Rolls back on any failure and returns the persisted payload on success.
  """

  alias Evhlegalchat.Repo
  alias Evhlegalchat.Agreement
  alias Evhlegalchat.SOW.{Deliverable, Milestone, PricingSchedule, RateCard, InvoicingTerm}
  import Ecto.Query

  @type sow_result :: %{
          optional(:deliverables) => list(map()),
          optional(:milestones) => list(map()),
          optional(:pricing_schedules) => list(map()),
          optional(:rate_cards) => list(map()),
          optional(:invoicing_terms) => map() | nil
        }

  @doc """
  Atomically creates an agreement and all SOW child rows. Rolls back on any failure.
  """
  @spec create_agreement_with_sow(map()) :: {:ok, %{agreement: Agreement.t(), sow: sow_result}} | {:error, term()}
  def create_agreement_with_sow(%{agreement: agr_attrs} = payload) when is_map(payload) do
    Repo.transaction(
      fn ->
        agreement = create_or_get_agreement!(agr_attrs)
        agreement_id = Map.get(agreement, :agreement_id) || Map.get(agreement, :id)

        sow_result =
          payload
          |> Map.put(:agreement_id, agreement_id)
          |> persist_sow_children!()

        _ = Evhlegalchat.Events.emit("agreement.created", %{agreement_id: agreement_id, doc_type: agreement.doc_type})

        maybe_emit_counts(sow_result)

        %{agreement: agreement, sow: sow_result}
      end,
      timeout: :infinity
    )
  rescue
    e -> {:error, e}
  end

  defp create_or_get_agreement!(attrs) do
    cs = Agreement.new_changeset(%Agreement{}, attrs)
    case Repo.insert(cs) do
      {:ok, agreement} -> agreement
      {:error, %Ecto.Changeset{errors: [source_hash: {_, [constraint: :unique, constraint_name: _]}]}} ->
        source_hash = Ecto.Changeset.get_field(cs, :source_hash)
        Repo.get_by!(Agreement, source_hash: source_hash)
      {:error, other} -> raise other
    end
  end

  defp persist_sow_children!(%{agreement_id: agreement_id} = payload) do
    now = DateTime.utc_now()

    deliverables =
      payload
      |> Map.get(:deliverables, [])
      |> List.wrap()
      |> Enum.map(&normalize_deliverable!(agreement_id, put_provenance(&1, payload, now), now))
      |> insert_all_returning(:sow_deliverables, [:deliverable_id, :title, :due_date])

    milestones =
      payload
      |> Map.get(:milestones, [])
      |> List.wrap()
      |> Enum.map(&normalize_milestone!(agreement_id, put_provenance(&1, payload, now), now))
      |> insert_all_returning(:sow_milestones, [:milestone_id, :title, :target_date])

    # patch depends_on by title/target_date → milestone_id within same transaction
    milestones = patch_milestone_dependencies!(agreement_id, milestones, payload[:milestones] || [])

    pricing_schedules =
      payload
      |> Map.get(:pricing_schedules, [])
      |> List.wrap()
      |> Enum.map(&normalize_pricing_schedule!(agreement_id, put_provenance(&1, payload, now), now))
      |> insert_all_returning(:sow_pricing_schedules, [:pricing_id, :pricing_model])

    rate_cards =
      payload
      |> Map.get(:rate_cards, [])
      |> List.wrap()
      |> Enum.map(&normalize_rate_card!(agreement_id, put_provenance(&1, payload, now), now))
      |> insert_all_returning(:sow_rate_cards, [:rate_card_id, :role, :effective_start])

    invoicing_terms =
      case Map.get(payload, :invoicing_terms) do
        nil -> nil
        terms ->
          [normalize_invoicing_term!(agreement_id, put_provenance(terms, payload, now), now)]
          |> insert_all_returning(:sow_invoicing_terms, [:invoicing_id, :billing_trigger])
          |> List.first()
      end

    %{
      deliverables: deliverables,
      milestones: milestones,
      pricing_schedules: pricing_schedules,
      rate_cards: rate_cards,
      invoicing_terms: invoicing_terms
    }
  end

  defp put_provenance(child_attrs, %{agreement: agr}, _now) when is_map(child_attrs) do
    child_attrs
    |> Map.put_new(:ingest_timestamp, agr[:ingest_timestamp])
    |> Map.put_new(:extractor_version, agr[:extractor_version])
    |> Map.put_new(:model_versions, agr[:model_versions])
  end
  defp put_provenance(child_attrs, _payload, _now), do: child_attrs

  defp maybe_emit_counts(%{deliverables: ds, milestones: ms, pricing_schedules: ps, rate_cards: rc} = _sow) do
    _ = Evhlegalchat.Events.emit("sow.deliverables.created", %{count: length(ds)})
    _ = Evhlegalchat.Events.emit("sow.milestones.created", %{count: length(ms)})
    _ = Evhlegalchat.Events.emit("sow.pricing_schedules.created", %{count: length(ps)})
    _ = Evhlegalchat.Events.emit("sow.rate_cards.created", %{count: length(rc)})
    :ok
  end

  defp insert_all_returning([], _table, _return_cols), do: []
  defp insert_all_returning(rows, table, return_cols) when is_list(rows) do
    {replace_cols, conflict_target} = conflict_policy_for(table)
    {_, returned} =
      Repo.insert_all(
        table,
        rows,
        on_conflict: {:replace, replace_cols},
        conflict_target: conflict_target,
        returning: return_cols
      )

    # Merge returned keys back onto rows based on conflict target natural keys
    index = Map.new(returned, fn r ->
      key = natural_key_for(table, r)
      {key, r}
    end)

    Enum.map(rows, fn r ->
      key = natural_key_for(table, r)
      Map.merge(r, Map.get(index, key, %{}))
    end)
  end

  defp conflict_policy_for(:sow_deliverables),
    do: {[:description, :artifact_type, :due_date, :acceptance_notes, :updated_at], [:agreement_id, :title]}

  defp conflict_policy_for(:sow_milestones),
    do: {[:description, :target_date, :depends_on, :updated_at], [:agreement_id, :title]}

  defp conflict_policy_for(:sow_pricing_schedules),
    do: {[:currency, :fixed_total, :not_to_exceed_total, :usage_unit, :usage_rate, :notes, :updated_at], [:agreement_id, :pricing_model]}

  defp conflict_policy_for(:sow_rate_cards),
    do: {[:hourly_rate, :currency, :effective_end, :updated_at], [:agreement_id, :role, :effective_start]}

  defp conflict_policy_for(:sow_invoicing_terms),
    do: {[:billing_trigger, :frequency, :net_terms_days, :late_fee_percent, :invoice_notes, :updated_at], [:agreement_id]}

  defp natural_key_for(:sow_deliverables, %{agreement_id: a, title: t}), do: {:sow_deliverables, a, t}
  defp natural_key_for(:sow_milestones, %{agreement_id: a, title: t}), do: {:sow_milestones, a, t}
  defp natural_key_for(:sow_pricing_schedules, %{agreement_id: a, pricing_model: m}), do: {:sow_pricing_schedules, a, m}
  defp natural_key_for(:sow_rate_cards, %{agreement_id: a, role: r, effective_start: s}), do: {:sow_rate_cards, a, r, s}
  defp natural_key_for(:sow_invoicing_terms, %{agreement_id: a}), do: {:sow_invoicing_terms, a}
  defp natural_key_for(_table, _row), do: {:unknown}

  # ————— Normalize rows —————

  defp normalize_deliverable!(agreement_id, attrs, now) do
    %{
      agreement_id: agreement_id,
      title: fetch_string!(attrs, :title, 255),
      description: safe_string(attrs[:description]),
      artifact_type: safe_string(attrs[:artifact_type]),
      due_date: coerce_date!(attrs[:due_date]),
      acceptance_notes: safe_string(attrs[:acceptance_notes]),
      inserted_at: now,
      updated_at: now
    }
  end

  defp normalize_milestone!(agreement_id, attrs, now) do
    %{
      agreement_id: agreement_id,
      title: fetch_string!(attrs, :title, 255),
      description: safe_string(attrs[:description]),
      target_date: coerce_date!(attrs[:target_date]),
      # depends_on is patched after insert
      inserted_at: now,
      updated_at: now
    }
  end

  defp normalize_pricing_schedule!(agreement_id, attrs, now) do
    %{
      agreement_id: agreement_id,
      pricing_model: normalize_pricing_model!(attrs[:pricing_model]),
      currency: normalize_currency(attrs[:currency] || "USD"),
      fixed_total: coerce_decimal!(attrs[:fixed_total]),
      not_to_exceed_total: coerce_decimal!(attrs[:not_to_exceed_total]),
      usage_unit: safe_string(attrs[:usage_unit]),
      usage_rate: coerce_decimal!(attrs[:usage_rate]),
      notes: safe_string(attrs[:notes]),
      inserted_at: now,
      updated_at: now
    }
  end

  defp normalize_rate_card!(agreement_id, attrs, now) do
    %{
      agreement_id: agreement_id,
      role: fetch_string!(attrs, :role, 100),
      hourly_rate: coerce_decimal!(attrs[:hourly_rate]),
      currency: normalize_currency(attrs[:currency] || "USD"),
      effective_start: coerce_date!(attrs[:effective_start]),
      effective_end: coerce_date!(attrs[:effective_end]),
      inserted_at: now,
      updated_at: now
    }
  end

  defp normalize_invoicing_term!(agreement_id, attrs, now) do
    %{
      agreement_id: agreement_id,
      billing_trigger: normalize_billing_trigger!(attrs[:billing_trigger]),
      frequency: safe_string(attrs[:frequency]),
      net_terms_days: coerce_integer!(attrs[:net_terms_days]),
      late_fee_percent: coerce_decimal!(attrs[:late_fee_percent]),
      invoice_notes: safe_string(attrs[:invoice_notes]),
      inserted_at: now,
      updated_at: now
    }
  end

  # ————— Milestone depends_on patching —————

  defp patch_milestone_dependencies!(_agreement_id, returned_milestones, []), do: returned_milestones
  defp patch_milestone_dependencies!(agreement_id, returned_milestones, input_milestones) do
    # map (title, target_date) -> milestone_id from returned rows (after upsert)
    idx =
      Map.new(returned_milestones, fn r ->
        {{r[:title], r[:target_date]}, r[:milestone_id]}
      end)

    # build updates where depends_on provided on input
    updates =
      input_milestones
      |> Enum.filter(&(Map.get(&1, :depends_on) not in [nil, ""]))
      |> Enum.map(fn m ->
        dep_title = m[:depends_on]
        key = {m[:title], coerce_date!(m[:target_date])}
        this_id = Map.get(idx, key)
        dep_id =
          idx
          |> Map.get({dep_title, nil}) || # fallback by title only if target_date not supplied
            find_milestone_id_by_title_and_date(agreement_id, dep_title, m[:target_date])

        {this_id, dep_id}
      end)
      |> Enum.filter(fn {a, b} -> is_integer(a) and is_integer(b) and a != b end)

    Enum.each(updates, fn {this_id, dep_id} ->
      from(mi in Milestone, where: mi.milestone_id == ^this_id)
      |> Repo.update_all(set: [depends_on: dep_id])
    end)

    # return latest rows after updates
    ids = Enum.map(returned_milestones, & &1[:milestone_id])
    from(mi in Milestone, where: mi.milestone_id in ^ids)
    |> select([mi], %{milestone_id: mi.milestone_id, title: mi.title, target_date: mi.target_date, depends_on: mi.depends_on})
    |> Repo.all()
  end

  defp find_milestone_id_by_title_and_date(agreement_id, title, target_date) do
    q =
      from mi in Milestone,
        where: mi.agreement_id == ^agreement_id and mi.title == ^title,
        select: mi.milestone_id,
        order_by: [desc: mi.inserted_at],
        limit: 1
    Repo.one(q)
  end

  # ————— Coercion helpers —————

  defp coerce_date!(nil), do: nil
  defp coerce_date!(%Date{} = d), do: d
  defp coerce_date!(s) when is_binary(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> raise ArgumentError, message: "Invalid date: #{inspect(s)}"
    end
  end

  defp coerce_decimal!(nil), do: nil
  defp coerce_decimal!(%Decimal{} = d), do: d
  defp coerce_decimal!(n) when is_integer(n), do: Decimal.new(n)
  defp coerce_decimal!(n) when is_float(n), do: Decimal.from_float(n)
  defp coerce_decimal!(s) when is_binary(s) do
    case Decimal.parse(String.trim(s)) do
      {:ok, d} -> d
      _ -> raise ArgumentError, message: "Invalid decimal: #{inspect(s)}"
    end
  end

  defp coerce_integer!(nil), do: nil
  defp coerce_integer!(n) when is_integer(n), do: n
  defp coerce_integer!(s) when is_binary(s) do
    case Integer.parse(String.trim(s)) do
      {n, _} -> n
      _ -> raise ArgumentError, message: "Invalid integer: #{inspect(s)}"
    end
  end

  defp fetch_string!(map, key, max_len) do
    v = Map.fetch!(map, key)
    s = safe_string(v)
    if is_binary(s) and String.length(s) <= max_len, do: s, else: raise ArgumentError, message: "Invalid string for #{inspect(key)}"
  end

  defp safe_string(nil), do: nil
  defp safe_string(v) when is_binary(v), do: v
  defp safe_string(v), do: to_string(v)

  defp normalize_currency(nil), do: "USD"
  defp normalize_currency(<<cur::binary>>) when byte_size(cur) <= 10, do: String.upcase(cur)

  defp normalize_pricing_model!(nil), do: raise ArgumentError, message: "pricing_model required"
  defp normalize_pricing_model!(pm) when is_atom(pm), do: normalize_pricing_model!(Atom.to_string(pm))
  defp normalize_pricing_model!(pm) when is_binary(pm) do
    case String.downcase(pm) do
      "fixed" -> "fixed_fee"
      "fixed_fee" -> "fixed_fee"
      "tm" -> "t_and_m"
      "t&m" -> "t_and_m"
      "t_and_m" -> "t_and_m"
      "not_to_exceed" -> "not_to_exceed"
      "usage" -> "usage_based"
      "usage_based" -> "usage_based"
      "hybrid" -> "hybrid"
      other -> raise ArgumentError, message: "Unsupported pricing_model: #{inspect(other)}"
    end
  end

  defp normalize_billing_trigger!(nil), do: raise ArgumentError, message: "billing_trigger required"
  defp normalize_billing_trigger!(bt) when is_atom(bt), do: normalize_billing_trigger!(Atom.to_string(bt))
  defp normalize_billing_trigger!(bt) when is_binary(bt) do
    case String.downcase(bt) do
      "milestone" -> "milestone"
      "calendar" -> "calendar"
      "usage" -> "usage"
      "on_acceptance" -> "on_acceptance"
      "advance" -> "advance"
      "completion" -> "completion"
      other -> raise ArgumentError, message: "Unsupported billing_trigger: #{inspect(other)}"
    end
  end
end


