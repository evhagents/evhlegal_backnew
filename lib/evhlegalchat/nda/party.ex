defmodule Evhlegalchat.NDA.Party do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:nda_party_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "nda_parties" do
    field :role, :string
    field :display_name, :string
    field :legal_name_norm, :string
    field :evidence_clause_id, :integer

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :role, :display_name, :legal_name_norm, :evidence_clause_id])
    |> validate_required([:agreement_id, :role, :display_name])
    |> validate_length(:role, max: 64)
    |> validate_length(:display_name, max: 255)
    |> validate_length(:legal_name_norm, max: 255)
  end
end


