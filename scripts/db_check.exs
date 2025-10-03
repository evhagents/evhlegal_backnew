alias Evhlegalchat.Repo

IO.puts("\nChecking database connection...")
db = Ecto.Adapters.SQL.query!(Repo, "select current_database()", [])
IO.inspect(db.rows, label: "current_database")

exists = Ecto.Adapters.SQL.query!(Repo, "select to_regclass('public.decision_rules')", [])
IO.inspect(exists.rows, label: "decision_rules_regclass")

tables = Ecto.Adapters.SQL.query!(Repo, "select table_name from information_schema.tables where table_schema = 'public' order by 1", [])
IO.inspect(Enum.take(tables.rows, 50), label: "public.tables (first 50)")


