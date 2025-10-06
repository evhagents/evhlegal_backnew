defmodule Evhlegalchat.SOW.ExpensesPolicy do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:expenses_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sow_expenses_policy" do
    field :reimbursable, :boolean, default: false
    field :preapproval_required, :boolean, default: false
    field :caps_notes, :string
    field :non_reimbursable, :string

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :reimbursable, :preapproval_required, :caps_notes, :non_reimbursable])
    |> validate_required([:agreement_id])
  end
end


