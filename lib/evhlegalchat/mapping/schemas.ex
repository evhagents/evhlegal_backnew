defmodule Evhlegalchat.Mapping.ExtractedFact do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:fact_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "extracted_facts" do
    field :agreement_id, :integer
    field :target_table, :string
    field :target_pk_name, :string
    field :target_pk_value, :integer
    field :target_column, :string

    field :raw_value, :string
    field :normalized_value, :string
    field :normalized_numeric, :decimal
    field :normalized_unit, :string

    field :evidence_clause_id, :integer
    field :evidence_start_char, :integer
    field :evidence_end_char, :integer
    field :evidence_start_page, :integer
    field :evidence_end_page, :integer

    field :confidence, :decimal
    field :status, Ecto.Enum, values: [:proposed, :applied, :rejected, :superseded], default: :proposed
    field :reason, :string

    field :extractor, :string
    field :extractor_version, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :agreement_id,
      :target_table,
      :target_pk_name,
      :target_pk_value,
      :target_column,
      :raw_value,
      :normalized_value,
      :normalized_numeric,
      :normalized_unit,
      :evidence_clause_id,
      :evidence_start_char,
      :evidence_end_char,
      :evidence_start_page,
      :evidence_end_page,
      :confidence,
      :status,
      :reason,
      :extractor,
      :extractor_version
    ])
    |> validate_required([
      :agreement_id,
      :target_table,
      :target_pk_name,
      :target_pk_value,
      :target_column,
      :confidence
    ])
    |> validate_length(:target_table, max: 64)
    |> validate_length(:target_pk_name, max: 64)
    |> validate_length(:target_column, max: 64)
    |> validate_length(:normalized_unit, max: 32)
    |> validate_length(:extractor, max: 64)
    |> validate_length(:extractor_version, max: 16)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end

defmodule Evhlegalchat.Mapping.ReviewTask do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:review_task_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "review_tasks" do
    field :agreement_id, :integer
    field :fact_id, :integer
    field :title, :string
    field :details, :map, default: %{}
    field :state, Ecto.Enum, values: [:open, :in_progress, :resolved], default: :open
    field :assignee_user_id, :integer
    field :resolution, :string
    field :resolved_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :agreement_id,
      :fact_id,
      :title,
      :details,
      :state,
      :assignee_user_id,
      :resolution,
      :resolved_at
    ])
    |> validate_required([:agreement_id, :title])
    |> validate_length(:title, max: 200)
  end
end

defmodule Evhlegalchat.Mapping.FieldAudit do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:field_audit_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "field_audit" do
    field :agreement_id, :integer
    field :target_table, :string
    field :target_pk_name, :string
    field :target_pk_value, :integer
    field :target_column, :string
    field :old_value, :string
    field :new_value, :string
    field :fact_id, :integer
    field :actor_user_id, :integer
    field :action, :string
    field :created_at, :utc_datetime_usec
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [
      :agreement_id,
      :target_table,
      :target_pk_name,
      :target_pk_value,
      :target_column,
      :old_value,
      :new_value,
      :fact_id,
      :actor_user_id,
      :action,
      :created_at
    ])
    |> validate_required([:agreement_id, :target_table, :target_pk_name, :target_pk_value, :target_column, :action])
    |> validate_length(:target_table, max: 64)
    |> validate_length(:target_pk_name, max: 64)
    |> validate_length(:target_column, max: 64)
    |> validate_length(:action, max: 32)
  end
end



