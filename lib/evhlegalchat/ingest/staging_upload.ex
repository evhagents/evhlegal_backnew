defmodule Evhlegalchat.Ingest.StagingUpload do
  @moduledoc """
  Schema for staging uploads before processing.
  
  Tracks uploaded files through the extraction pipeline with deduplication
  based on SHA256 source hash.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:staging_upload_id, :integer, autogenerate: false}

  @allowed_statuses [:uploaded, :scanning, :ready_for_extraction, :extracting, :extracted, :promoted, :rejected, :error]
  @allowed_scan_statuses [:skipped, :clean, :infected]

  schema "staging_uploads" do
    field :status, Ecto.Enum, values: @allowed_statuses, default: :uploaded
    field :scan_status, Ecto.Enum, values: @allowed_scan_statuses, default: :skipped
    field :source_hash, :string
    field :storage_key, :string
    field :content_type_detected, :string
    field :original_filename, :string
    field :byte_size, :integer
    field :rejection_reason, :string
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Creates a changeset for staging upload validation.
  """
  def changeset(%__MODULE__{} = staging_upload, attrs) do
    staging_upload
    |> cast(attrs, [
      :status,
      :scan_status,
      :source_hash,
      :storage_key,
      :content_type_detected,
      :original_filename,
      :byte_size,
      :rejection_reason,
      :metadata
    ])
    |> validate_required([
      :source_hash,
      :storage_key,
      :content_type_detected,
      :original_filename,
      :byte_size
    ])
    |> validate_length(:source_hash, is: 64)
    |> validate_length(:storage_key, max: 512)
    |> validate_length(:content_type_detected, max: 128)
    |> validate_length(:original_filename, max: 255)
    |> validate_number(:byte_size, greater_than: 0)
    |> unique_constraint(:source_hash)
  end

  @doc """
  Creates a changeset for a new staging upload record.
  """
  def new_changeset(attrs) do
    changeset(%__MODULE__{}, attrs)
  end

  @doc """
  Checks if the upload is in a terminal state.
  """
  def terminal_status?(%__MODULE__{status: status}) do
    status in [:extracted, :promoted, :rejected, :error]
  end

  @doc """
  Gets a human-readable status description.
  """
  def status_description(%__MODULE__{status: status}) do
    case status do
      :uploaded -> "File uploaded"
      :scanning -> "Scanning for threats"
      :ready_for_extraction -> "Ready for extraction"
      :extracting -> "Extracting content"
      :extracted -> "Content extracted"
      :promoted -> "Promoted to production"
      :rejected -> "Upload rejected"
      :error -> "Processing error"
    end
  end
end