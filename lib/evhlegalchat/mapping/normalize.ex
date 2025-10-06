defmodule Evhlegalchat.Mapping.Normalize do
  @moduledoc """
  Normalization helpers for dates, durations, and currency.
  """

  @month_words %{"month" => 1, "months" => 1, "year" => 12, "years" => 12}

  @doc """
  Parse a duration string like "two (2) years" into {months, unit}.
  Returns {:ok, %{numeric: months, unit: "months", normalized: "<n> months"}} or :error.
  """
  def parse_duration_to_months(text) when is_binary(text) do
    with {:ok, qty} <- extract_quantity(text),
         {:ok, mult} <- extract_unit_multiplier(text) do
      months = qty * mult
      {:ok, %{numeric: months, unit: "months", normalized: "#{months} months"}}
    else
      _ -> :error
    end
  end

  defp extract_quantity(text) do
    case Regex.run(~r/\b(\d{1,3})(?:\.\d+)?\b/, text) do
      [_, num] -> {:ok, String.to_integer(num)}
      _ ->
        words = %{"one" => 1, "two" => 2, "three" => 3, "four" => 4, "five" => 5, "six" => 6, "seven" => 7, "eight" => 8, "nine" => 9, "ten" => 10, "twelve" => 12, "twenty-four" => 24}
        case Enum.find(words, fn {w, _} -> String.contains?(String.downcase(text), w) end) do
          {_, n} -> {:ok, n}
          _ -> :error
        end
    end
  end

  defp extract_unit_multiplier(text) do
    unit =
      cond do
        String.match?(String.downcase(text), ~r/\byear/) -> "year"
        String.match?(String.downcase(text), ~r/\bmonth/) -> "month"
        true -> nil
      end

    case unit && Map.get(@month_words, unit) do
      nil -> :error
      mult -> {:ok, mult}
    end
  end

  @doc """
  Parse a date in common formats without external deps. Returns {:ok, %Date{}} or :error.
  Supports: YYYY-MM-DD, M/D/YYYY, Month D, YYYY.
  """
  def parse_date(text) when is_binary(text) do
    with {:ok, d} <- parse_iso(text) do
      {:ok, d}
    else
      _ -> parse_slash(text) || parse_long(text) || :error
    end
  end

  defp parse_iso(text) do
    case Date.from_iso8601(text) do
      {:ok, d} -> {:ok, d}
      _ -> :error
    end
  end

  defp parse_slash(text) do
    case Regex.run(~r/^\s*(\d{1,2})\/(\d{1,2})\/(\d{4})\s*$/, text) do
      [_, m, d, y] -> Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d))
      _ -> nil
    end
  end

  @months %{
    "january" => 1, "february" => 2, "march" => 3, "april" => 4, "may" => 5, "june" => 6,
    "july" => 7, "august" => 8, "september" => 9, "october" => 10, "november" => 11, "december" => 12,
    "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4, "jun" => 6, "jul" => 7, "aug" => 8,
    "sep" => 9, "sept" => 9, "oct" => 10, "nov" => 11, "dec" => 12
  }

  defp parse_long(text) do
    case Regex.run(~r/^\s*([A-Za-z]+)\s+(\d{1,2}),\s*(\d{4})\s*$/, text) do
      [_, mon, d, y] ->
        with m when is_integer(m) <- Map.get(@months, String.downcase(mon)) do
          Date.new(String.to_integer(y), m, String.to_integer(d))
        end
      _ -> nil
    end
  end

  @doc """
  Parse currency strings like "$1,200.50" -> {:ok, %{cents: 120050, currency: "USD"}}
  """
  def parse_currency(text) when is_binary(text) do
    cleaned = String.trim(text)
    {currency, number} =
      cond do
        String.starts_with?(cleaned, "$") -> {"USD", String.trim_leading(cleaned, "$")}
        String.starts_with?(cleaned, "USD") -> {"USD", String.replace_prefix(cleaned, "USD", "")}
        true -> {"USD", cleaned}
      end

    case Decimal.parse(String.replace(number, ",", "")) do
      {:ok, dec} ->
        cents = dec |> Decimal.mult(Decimal.new(100)) |> Decimal.to_integer()
        {:ok, %{cents: cents, currency: currency}}
      _ -> :error
    end
  end
end


