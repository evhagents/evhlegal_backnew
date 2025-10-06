defmodule Evhlegalchat.Mapping.Router do
  @moduledoc """
  Routes facts to the correct applier.
  """
  alias Evhlegalchat.Mapping.Apply
  def route_and_apply(fact), do: Apply.apply_fact(fact)
end



