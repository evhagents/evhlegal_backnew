defmodule Evhlegalchat.NDA.KeyClause do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:nda_key_clause_id, :id, autogenerate: true}
  @foreign_key_type :id

  @keys ~w(
    definition_confidential_information
    use_restrictions
    term_duration
    return_or_destroy
    injunctive_relief
    governing_law
    venue
    no_license
  )a

  schema "nda_key_clauses" do
    field :key, Ecto.Enum, values: @keys
    field :value_text, :string
    field :value_numeric, :decimal
    field :value_unit, :string
    field :evidence_clause_id, :integer
    field :confidence, :decimal
    field :ingest_timestamp, :utc_datetime_usec
    field :extractor_version, :string
    field :model_versions, :map

    belongs_to :agreement, Evhlegalchat.Agreement, define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:agreement_id, :key, :value_text, :value_numeric, :value_unit, :evidence_clause_id, :confidence, :ingest_timestamp, :extractor_version, :model_versions])
    |> validate_required([:agreement_id, :key])
    |> validate_length(:value_unit, max: 32)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> unique_constraint([:agreement_id, :key])
  end
end


