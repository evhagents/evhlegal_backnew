defmodule Evhlegalchat.Agreement do
  @moduledoc """
  Schema for canonical agreements after promotion from staging.

  Represents the final, processed legal documents with all extracted
  metadata and provenance information.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  @allowed_doc_types [:NDA, :SOW]
  @allowed_statuses [:draft, :executed, :terminated, :archived]
  @allowed_review_statuses [:unreviewed, :needs_review, :approved]

  schema "agreements" do
    field :doc_type, Ecto.Enum, values: @allowed_doc_types
    field :agreement_title, :string
    field :effective_date, :date
    field :governing_law, :string
    field :venue, :string
    field :term_length_months, :integer
    field :early_termination_allowed, :boolean, default: false
    field :early_termination_notice, :string
    field :survival_period_months, :integer
    field :status, Ecto.Enum, values: @allowed_statuses, default: :draft
    field :transaction_context, :map, default: %{}
    field :source_file_name, :string
    field :source_hash, :string
    field :ingest_timestamp, :utc_datetime_usec
    field :extractor_version, :string
    field :model_versions, :map, default: %{}
    field :review_status, Ecto.Enum, values: @allowed_review_statuses, default: :unreviewed
    field :reviewer_notes, :string
    field :storage_key, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for agreement validation.
  """
  def changeset(%__MODULE__{} = agreement, attrs) do
    agreement
    |> cast(attrs, [
      :doc_type,
      :agreement_title,
      :effective_date,
      :governing_law,
      :venue,
      :term_length_months,
      :early_termination_allowed,
      :early_termination_notice,
      :survival_period_months,
      :status,
      :transaction_context,
      :source_file_name,
      :source_hash,
      :ingest_timestamp,
      :extractor_version,
      :model_versions,
      :review_status,
      :reviewer_notes,
      :storage_key
    ])
    |> validate_required([
      :doc_type,
      :agreement_title,
      :source_file_name,
      :source_hash,
      :ingest_timestamp,
      :extractor_version
    ])
    |> validate_length(:agreement_title, max: 255)
    |> validate_length(:source_file_name, max: 255)
    |> validate_length(:source_hash, is: 64)
    |> validate_length(:extractor_version, max: 20)
    |> validate_length(:storage_key, max: 512)
    |> validate_length(:governing_law, max: 100)
    |> validate_length(:venue, max: 100)
    |> validate_length(:early_termination_notice, max: 100)
    |> validate_number(:term_length_months, greater_than: 0)
    |> validate_number(:survival_period_months, greater_than: 0)
    |> unique_constraint(:source_hash)
  end

  @doc """
  Creates a changeset for a new agreement record.
  """
  def new_changeset(attrs) do
    changeset(%__MODULE__{}, attrs)
  end
end