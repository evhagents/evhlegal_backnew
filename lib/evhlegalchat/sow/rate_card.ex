defmodule Evhlegalchat.SOW.RateCard do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:rate_card_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sow_rate_cards" do
    field :role, :string
    field :hourly_rate, :decimal
    field :currency, :string, default: "USD"
    field :effective_start, :date
    field :effective_end, :date
    field :ingest_timestamp, :utc_datetime_usec
    field :extractor_version, :string
    field :model_versions, :map

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :role, :hourly_rate, :currency, :effective_start, :effective_end, :ingest_timestamp, :extractor_version, :model_versions])
    |> validate_required([:agreement_id, :role, :hourly_rate, :effective_start])
    |> validate_length(:role, max: 100)
    |> validate_length(:currency, max: 10)
  end
end


