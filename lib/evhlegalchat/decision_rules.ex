defmodule Evhlegalchat.DecisionRules do
  @moduledoc """
  Context for working with decision rules.
  """

  import Ecto.Query, warn: false
  alias Evhlegalchat.Repo

  alias Evhlegalchat.DecisionRules.DecisionRule

  @spec change_decision_rule(DecisionRule.t(), map()) :: Ecto.Changeset.t()
  def change_decision_rule(%DecisionRule{} = decision_rule, attrs \\ %{}) do
    DecisionRule.changeset(decision_rule, attrs)
  end

  @spec create_decision_rule(map()) :: {:ok, DecisionRule.t()} | {:error, Ecto.Changeset.t()}
  def create_decision_rule(attrs) when is_map(attrs) do
    %DecisionRule{}
    |> DecisionRule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns the most recent decision rules, default 3.

  Note: ordered by id desc to avoid relying on timestamps.
  """
  @spec list_recent_decision_rules(pos_integer()) :: [DecisionRule.t()]
  def list_recent_decision_rules(limit \\ 3) when is_integer(limit) and limit > 0 do
    DecisionRule
    |> order_by([d], desc: d.id)
    |> limit(^limit)
    |> Repo.all()
  end
end
