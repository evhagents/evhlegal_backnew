defmodule Evhlegalchat.SOW.ChangeRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:cr_id, :id, autogenerate: true}
  @foreign_key_type :id

  @statuses [:draft, :submitted, :approved, :rejected, :withdrawn, :superseded]

  schema "sow_change_requests" do
    field :title, :string
    field :description, :string
    field :scope_delta, :string
    field :price_delta, :decimal
    field :time_delta_days, :integer
    field :status, Ecto.Enum, values: @statuses, default: :draft
    field :submitted_by, :string
    field :approved_by, :string
    field :approved_at, :utc_datetime
    field :supersedes_cr_id, :integer

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :title, :description, :scope_delta, :price_delta, :time_delta_days, :status, :submitted_by, :approved_by, :approved_at, :supersedes_cr_id])
    |> validate_required([:agreement_id, :title])
    |> validate_length(:title, max: 255)
  end
end


