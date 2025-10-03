defmodule Evhlegalchat.DecisionRules.DecisionRule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "decision_rules" do
    field :id_slug, :string
    field :version, :string

    field :status, Ecto.Enum, values: [:draft, :active, :deprecated]
    field :priority, Ecto.Enum, values: [:critical, :high, :medium, :low]

    field :da_rule, :string
    field :created_by, :string
  end

  @doc false
  def changeset(%__MODULE__{} = decision_rule, attrs) do
    decision_rule
    |> cast(attrs, [:id_slug, :version, :status, :priority, :da_rule, :created_by])
    |> validate_required([:id_slug, :version, :status, :priority])
  end
end
