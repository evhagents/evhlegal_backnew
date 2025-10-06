defmodule Evhlegalchat.NDA.Signature do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:nda_signature_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "nda_signatures" do
    field :signer_name, :string
    field :signer_title, :string
    field :party_name, :string
    field :signed_date, :date
    field :evidence_clause_id, :integer
    field :confidence, :decimal

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :signer_name, :signer_title, :party_name, :signed_date, :evidence_clause_id, :confidence])
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_length(:signer_name, max: 255)
    |> validate_length(:signer_title, max: 255)
    |> validate_length(:party_name, max: 255)
  end
end


