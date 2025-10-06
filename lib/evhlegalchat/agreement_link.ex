defmodule Evhlegalchat.AgreementLink do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:agreement_link_id, :id, autogenerate: true}
  @foreign_key_type :id

  @types [:supersedes, :amends, :related]

  schema "agreement_links" do
    field :link_type, Ecto.Enum, values: @types
    field :notes, :string

    belongs_to :from_agreement, Evhlegalchat.Agreement, define_field: false
    belongs_to :to_agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:from_agreement_id, :to_agreement_id, :link_type, :notes])
    |> validate_required([:from_agreement_id, :to_agreement_id, :link_type])
    |> validate_inclusion(:link_type, @types)
    |> unique_constraint([:from_agreement_id, :to_agreement_id, :link_type], name: :agreement_links_uq_pair)
  end
end


