defmodule Evhlegalchat.SOW.Deliverable do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:deliverable_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sow_deliverables" do
    field :title, :string
    field :description, :string
    field :artifact_type, :string
    field :due_date, :date
    field :acceptance_notes, :string
    field :ingest_timestamp, :utc_datetime_usec
    field :extractor_version, :string
    field :model_versions, :map

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :title, :description, :artifact_type, :due_date, :acceptance_notes, :ingest_timestamp, :extractor_version, :model_versions])
    |> validate_required([:agreement_id, :title])
    |> validate_length(:title, max: 255)
    |> validate_length(:artifact_type, max: 100)
  end
end


