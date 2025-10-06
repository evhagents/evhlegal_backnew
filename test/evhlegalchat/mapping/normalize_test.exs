defmodule Evhlegalchat.Mapping.NormalizeTest do
  use ExUnit.Case, async: true
  alias Evhlegalchat.Mapping.Normalize

  test "duration two years -> 24 months" do
    assert {:ok, %{numeric: 24, unit: "months"}} = Normalize.parse_duration_to_months("two (2) years")
  end

  test "currency parses" do
    assert {:ok, %{cents: 120050, currency: "USD"}} = Normalize.parse_currency("$1,200.50")
  end
end



