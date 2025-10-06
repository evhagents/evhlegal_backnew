defmodule Evhlegalchat.Mapping.ConflictsTest do
  use ExUnit.Case, async: true
  alias Evhlegalchat.Mapping.Conflicts

  test "higher confidence applies" do
    new = %{confidence: Decimal.new("0.9"), status: :proposed}
    old = %{confidence: Decimal.new("0.7"), status: :applied}
    assert :apply = Conflicts.decide(new, old)
  end

  test "equal confidence tie prefer newer" do
    new = %{confidence: Decimal.new("0.8"), status: :proposed}
    old = %{confidence: Decimal.new("0.8"), status: :applied}
    assert :supersede_old = Conflicts.decide(new, old)
  end
end



