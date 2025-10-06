defmodule Evhlegalchat.NDA.Carveout do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:carveout_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "nda_carveouts" do
    field :label, :string
    field :text, :string
    field :evidence_clause_id, :integer
    field :confidence, :decimal

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :label, :text, :evidence_clause_id, :confidence])
    |> validate_required([:agreement_id, :text])
    |> validate_length(:label, max: 128)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end


