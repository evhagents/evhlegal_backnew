defmodule Evhlegalchat.SOW.Assumption do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:assumption_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sow_assumptions" do
    field :category, :string
    field :text, :string
    field :risk_if_breached, :string

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :category, :text, :risk_if_breached])
    |> validate_required([:agreement_id, :text])
    |> validate_length(:category, max: 100)
  end
end


