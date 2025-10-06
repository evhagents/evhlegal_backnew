defmodule Evhlegalchat.SOW.Milestone do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:milestone_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sow_milestones" do
    field :title, :string
    field :description, :string
    field :target_date, :date
    field :depends_on, :integer
    field :ingest_timestamp, :utc_datetime_usec
    field :extractor_version, :string
    field :model_versions, :map

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :title, :description, :target_date, :depends_on, :ingest_timestamp, :extractor_version, :model_versions])
    |> validate_required([:agreement_id, :title])
    |> validate_length(:title, max: 255)
  end
end


