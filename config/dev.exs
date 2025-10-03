import Config

# Configure your database
config :evhlegalchat, Evhlegalchat.Repo,
  url: "postgresql://masteruser:ObFzxQlAbQXHNCWZkRINuAmVtvGw28GU@dpg-d3b9ga56ubrc739ieb20-a.oregon-postgres.render.com/masterpostgres",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  ssl: true

# For development, we disable any cache and enable
# debugging and code reloading.
config :evhlegalchat, EvhlegalchatWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "SECRET_KEY_BASE"

# Watch static and templates for browser reloading.
config :evhlegalchat, EvhlegalchatWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/evhlegalchat_web/(?:controllers|router)/?.*\.(ex)$"
    ]
  ]

# Enable dev routes for dashboard
config :evhlegalchat, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false