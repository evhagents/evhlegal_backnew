import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :evhlegalchat, EvhlegalchatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-secret-key",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure your database
config :evhlegalchat, Evhlegalchat.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "evhlegalchat_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We use a file-based database for testing
# config :evhlegalchat, Evhlegalchat.Repo,
#   adapter: Ecto.Adapters.SQLite3,
#   database: "priv/test.db"

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
