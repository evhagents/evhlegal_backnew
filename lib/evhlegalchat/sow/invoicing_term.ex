defmodule Evhlegalchat.SOW.InvoicingTerm do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:invoicing_id, :id, autogenerate: true}
  @foreign_key_type :id

  @triggers [:milestone, :calendar, :usage, :on_acceptance, :advance, :completion]

  schema "sow_invoicing_terms" do
    field :billing_trigger, Ecto.Enum, values: @triggers
    field :frequency, :string
    field :net_terms_days, :integer
    field :late_fee_percent, :decimal
    field :invoice_notes, :string
    field :ingest_timestamp, :utc_datetime_usec
    field :extractor_version, :string
    field :model_versions, :map

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :billing_trigger, :frequency, :net_terms_days, :late_fee_percent, :invoice_notes, :ingest_timestamp, :extractor_version, :model_versions])
    |> validate_required([:agreement_id, :billing_trigger])
    |> validate_length(:frequency, max: 50)
  end
end


