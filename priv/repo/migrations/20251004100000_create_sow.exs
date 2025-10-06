defmodule Evhlegalchat.Repo.Migrations.CreateSow do
  use Ecto.Migration

  def change do
    # Enums
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pricing_model') THEN
        CREATE TYPE pricing_model AS ENUM ('fixed_fee', 't_and_m', 'not_to_exceed', 'usage_based', 'hybrid');
      END IF;
    END$$;
    """, "DROP TYPE IF EXISTS pricing_model"

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'billing_trigger') THEN
        CREATE TYPE billing_trigger AS ENUM ('milestone', 'calendar', 'usage', 'on_acceptance', 'advance', 'completion');
      END IF;
    END$$;
    """, "DROP TYPE IF EXISTS billing_trigger"

    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'cr_status') THEN
        CREATE TYPE cr_status AS ENUM ('draft','submitted','approved','rejected','withdrawn','superseded');
      END IF;
    END$$;
    """, "DROP TYPE IF EXISTS cr_status"

    # Deliverables
    create_if_not_exists table(:sow_deliverables, primary_key: false) do
      add :deliverable_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :title, :string, size: 255, null: false
      add :description, :text
      add :artifact_type, :string, size: 100
      add :due_date, :date
      add :acceptance_notes, :text
      timestamps(type: :utc_datetime_usec)
    end

execute """
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sow_deliverables' 
    AND column_name = 'deliverable_id' 
    AND is_identity = 'YES'
  ) THEN
    ALTER TABLE sow_deliverables ALTER COLUMN deliverable_id ADD GENERATED ALWAYS AS IDENTITY;
  END IF;
END $$;
"""
    create_if_not_exists index(:sow_deliverables, [:agreement_id])
    create_if_not_exists unique_index(:sow_deliverables, [:agreement_id, :title], name: :sow_deliverables_uq_title)

    # Milestones
    create_if_not_exists table(:sow_milestones, primary_key: false) do
      add :milestone_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :title, :string, size: 255, null: false
      add :description, :text
      add :target_date, :date
      add :depends_on, references(:sow_milestones, column: :milestone_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

execute """
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sow_milestones' 
    AND column_name = 'milestone_id' 
    AND is_identity = 'YES'
  ) THEN
    ALTER TABLE sow_milestones ALTER COLUMN milestone_id ADD GENERATED ALWAYS AS IDENTITY;
  END IF;
END $$;
"""
    create_if_not_exists index(:sow_milestones, [:agreement_id])
    create_if_not_exists unique_index(:sow_milestones, [:agreement_id, :title], name: :sow_milestones_uq_title)

    # Pricing schedules
    create_if_not_exists table(:sow_pricing_schedules, primary_key: false) do
      add :pricing_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :pricing_model, :pricing_model, null: false
      add :currency, :string, size: 10, default: "USD"
      add :fixed_total, :decimal, precision: 14, scale: 2
      add :not_to_exceed_total, :decimal, precision: 14, scale: 2
      add :usage_unit, :string, size: 64
      add :usage_rate, :decimal, precision: 14, scale: 6
      add :notes, :text
      timestamps(type: :utc_datetime_usec)
    end

execute """
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sow_pricing_schedules' 
    AND column_name = 'pricing_id' 
    AND is_identity = 'YES'
  ) THEN
    ALTER TABLE sow_pricing_schedules ALTER COLUMN pricing_id ADD GENERATED ALWAYS AS IDENTITY;
  END IF;
END $$;
"""    
create_if_not_exists index(:sow_pricing_schedules, [:agreement_id])
    create_if_not_exists unique_index(:sow_pricing_schedules, [:agreement_id, :pricing_model], name: :sow_pricing_uq_model)

    # Rate cards
    create_if_not_exists table(:sow_rate_cards, primary_key: false) do
      add :rate_card_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :role, :string, size: 100, null: false
      add :hourly_rate, :decimal, precision: 12, scale: 2, null: false
      add :currency, :string, size: 10, default: "USD"
      add :effective_start, :date, null: false
      add :effective_end, :date
      timestamps(type: :utc_datetime_usec)
    end

execute """
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sow_rate_cards' 
    AND column_name = 'rate_card_id' 
    AND is_identity = 'YES'
  ) THEN
    ALTER TABLE sow_rate_cards ALTER COLUMN rate_card_id ADD GENERATED ALWAYS AS IDENTITY;
  END IF;
END $$;
"""
    create_if_not_exists index(:sow_rate_cards, [:agreement_id])
    create_if_not_exists unique_index(:sow_rate_cards, [:agreement_id, :role, :effective_start], name: :sow_rate_cards_uq_role_start)

    # Invoicing terms
    create_if_not_exists table(:sow_invoicing_terms, primary_key: false) do
      add :invoicing_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :billing_trigger, :billing_trigger, null: false
      add :frequency, :string, size: 50
      add :net_terms_days, :integer
      add :late_fee_percent, :decimal, precision: 5, scale: 2
      add :invoice_notes, :text
      timestamps(type: :utc_datetime_usec)
    end

execute """
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sow_invoicing_terms' 
    AND column_name = 'invoicing_id' 
    AND is_identity = 'YES'
  ) THEN
    ALTER TABLE sow_invoicing_terms ALTER COLUMN invoicing_id ADD GENERATED ALWAYS AS IDENTITY;
  END IF;
END $$;
"""
    create_if_not_exists index(:sow_invoicing_terms, [:agreement_id])
    create_if_not_exists unique_index(:sow_invoicing_terms, [:agreement_id, :billing_trigger], name: :sow_invoicing_uq_trigger)

    # Expenses policy
    create_if_not_exists table(:sow_expenses_policy, primary_key: false) do
      add :expenses_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :reimbursable, :boolean, default: false
      add :preapproval_required, :boolean, default: false
      add :caps_notes, :text
      add :non_reimbursable, :text
      timestamps(type: :utc_datetime_usec)
    end

execute """
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sow_expenses_policy' 
    AND column_name = 'expenses_id' 
    AND is_identity = 'YES'
  ) THEN
    ALTER TABLE sow_expenses_policy ALTER COLUMN expenses_id ADD GENERATED ALWAYS AS IDENTITY;
  END IF;
END $$;
"""    
create_if_not_exists unique_index(:sow_expenses_policy, [:agreement_id], name: :sow_expenses_policy_uq_agreement)

    # Change requests
    create_if_not_exists table(:sow_change_requests, primary_key: false) do
      add :cr_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :title, :string, size: 255, null: false
      add :description, :text
      add :scope_delta, :text
      add :price_delta, :decimal, precision: 14, scale: 2
      add :time_delta_days, :integer
      add :status, :cr_status, null: false, default: "draft"
      add :submitted_by, :string, size: 255
      add :approved_by, :string, size: 255
      add :approved_at, :utc_datetime
      add :supersedes_cr_id, references(:sow_change_requests, column: :cr_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

execute """
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sow_change_requests' 
    AND column_name = 'cr_id' 
    AND is_identity = 'YES'
  ) THEN
    ALTER TABLE sow_change_requests ALTER COLUMN cr_id ADD GENERATED ALWAYS AS IDENTITY;
  END IF;
END $$;
"""    
    create_if_not_exists index(:sow_change_requests, [:agreement_id])
    create_if_not_exists unique_index(:sow_change_requests, [:agreement_id, :title], name: :sow_cr_uq_title)

    # Assumptions
    create_if_not_exists table(:sow_assumptions, primary_key: false) do
      add :assumption_id, :integer, primary_key: true
      add :agreement_id, references(:agreements, column: :agreement_id, on_delete: :delete_all), null: false
      add :category, :string, size: 100
      add :text, :text, null: false
      add :risk_if_breached, :text
      timestamps(type: :utc_datetime_usec)
    end

execute """
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'sow_assumptions' 
    AND column_name = 'assumption_id' 
    AND is_identity = 'YES'
  ) THEN
    ALTER TABLE sow_assumptions ALTER COLUMN assumption_id ADD GENERATED ALWAYS AS IDENTITY;
  END IF;
END $$;
"""    
    create_if_not_exists index(:sow_assumptions, [:agreement_id])
    create_if_not_exists unique_index(:sow_assumptions, [:agreement_id, :text], name: :sow_assumptions_uq_text)
  end
end


