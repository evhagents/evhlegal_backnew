defmodule Evhlegalchat.SOW.PricingSchedule do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:pricing_id, :id, autogenerate: true}
  @foreign_key_type :id

  @pricing_models [:fixed_fee, :t_and_m, :not_to_exceed, :usage_based, :hybrid]

  schema "sow_pricing_schedules" do
    field :pricing_model, Ecto.Enum, values: @pricing_models
    field :currency, :string, default: "USD"
    field :fixed_total, :decimal
    field :not_to_exceed_total, :decimal
    field :usage_unit, :string
    field :usage_rate, :decimal
    field :notes, :string
    field :ingest_timestamp, :utc_datetime_usec
    field :extractor_version, :string
    field :model_versions, :map

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :pricing_model, :currency, :fixed_total, :not_to_exceed_total, :usage_unit, :usage_rate, :notes, :ingest_timestamp, :extractor_version, :model_versions])
    |> validate_required([:agreement_id, :pricing_model])
    |> validate_length(:currency, max: 10)
    |> validate_length(:usage_unit, max: 64)
  end
end


