defmodule Evhlegalchat.Repo.Migrations.CreateDecisionRules do
  use Ecto.Migration

  def change do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "DROP EXTENSION IF EXISTS pgcrypto")

    create_if_not_exists table(:decision_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :id_slug, :text, null: false
      add :version, :text, null: false

      # Stored as strings; validated via check constraints
      add :status, :string, null: false
      add :priority, :string, null: false

      add :da_rule, :text
      add :created_by, :text
    end

    create_if_not_exists constraint(:decision_rules, :status_allowed_values,
             check: "status in ('draft','active','deprecated')"
           )

    create_if_not_exists constraint(:decision_rules, :priority_allowed_values,
             check: "priority in ('critical','high','medium','low')"
           )
  end
end
