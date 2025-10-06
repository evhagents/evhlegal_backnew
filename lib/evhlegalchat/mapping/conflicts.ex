defmodule Evhlegalchat.Mapping.Conflicts do
  @moduledoc """
  Conflict detection and resolution policies.
  """
  alias Evhlegalchat.Mapping.Config

  @type decision :: :apply | :keep_existing | :supersede_old | :reject

  def decide(%{confidence: conf_new} = _new, existing_fact_or_nil, opts \\ []) do
    conf = Config.fetch()
    allow_downgrade = Keyword.get(opts, :allow_downgrade, conf[:allow_downgrade])
    prefer_newer_equal = Keyword.get(opts, :prefer_newer_equal_conf, conf[:prefer_newer_equal_conf])

    case existing_fact_or_nil do
      nil ->
        :apply

      %{status: :applied, confidence: conf_old} = _old ->
        cmp = Decimal.compare(as_decimal(conf_new), as_decimal(conf_old))
        case cmp do
          :gt -> if allow_downgrade, do: :apply, else: :apply
          :lt -> :keep_existing
          :eq -> if prefer_newer_equal, do: :supersede_old, else: :keep_existing
        end

      %{status: :proposed} -> :apply
      %{status: :rejected} -> :apply
      %{status: :superseded} -> :apply
    end
  end

  def protected_column?(target_table, target_column) do
    conf = Config.fetch()
    protected = conf[:protected_columns] || %{}
    cols = Map.get(protected, target_table, [])
    Enum.member?(cols, String.to_atom(target_column))
  end

  defp as_decimal(%Decimal{} = d), do: d
  defp as_decimal(n) when is_float(n), do: Decimal.from_float(n)
  defp as_decimal(n) when is_integer(n), do: Decimal.new(n)
  defp as_decimal(n) when is_binary(n), do: Decimal.new(n)
end



