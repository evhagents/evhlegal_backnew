defmodule Evhlegalchat.Repo.Migrations.CreateNdaAnatomy do
  use Ecto.Migration

  def change do
    create_if_not_exists table("nda_anatomy") do
      add :original_name, :text, null: false
      add :party_disclosing, :text
      add :party_receiving, :text
      add :effective_date, :date
      add :definitions, :text
      add :confidential_information, :text
      add :exclusions, :text
      add :obligations, :text
      add :term, :text
      add :return_of_materials, :text
      add :remedies, :text
      add :governing_law, :text
      add :miscellaneous, :text
      add :raw_text, :text
      add :parsed_json, :jsonb
      add :search_vector, :tsvector

      timestamps()
    end
  end
end
