defmodule Evhlegalchat.Nda.NdaAnatomy do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nda_anatomy" do
    field :original_name, :string
    field :party_disclosing, :string
    field :party_receiving, :string
    field :effective_date, :date
    field :definitions, :string
    field :confidential_information, :string
    field :exclusions, :string
    field :obligations, :string
    field :term, :string
    field :return_of_materials, :string
    field :remedies, :string
    field :governing_law, :string
    field :miscellaneous, :string
    field :raw_text, :string
    field :parsed_json, :map
    field :search_vector, :string

    timestamps()
  end

  @doc false
  def changeset(%__MODULE__{} = nda_anatomy, attrs) do
    nda_anatomy
    |> cast(attrs, [
      :original_name,
      :party_disclosing,
      :party_receiving,
      :effective_date,
      :definitions,
      :confidential_information,
      :exclusions,
      :obligations,
      :term,
      :return_of_materials,
      :remedies,
      :governing_law,
      :miscellaneous,
      :raw_text,
      :parsed_json,
      :search_vector
    ])
    |> validate_required([:original_name])
  end
end
