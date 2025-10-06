# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config
config :evhlegalchat, Evhlegalchat.Enrich,
  nda: [
    min_confidence_numeric: 0.6,
    party_role_defaults: :mutual
  ],
  sow: [
    min_confidence_numeric: 0.6,
    deliverable_title_max: 255
  ],
  common: [
    heading_matchers: [
      nda_term: ~r/^(term|duration)/i,
      deliverables: ~r/^deliverables?|^scope of work/i,
      milestones: ~r/^milestones?/i,
      pricing: ~r/^pricing|^fees|^compensation/i,
      invoicing: ~r/^invoic/i,
      expenses: ~r/^expenses?/i,
      assumptions: ~r/^assumptions?|^dependencies/i,
      signatures: ~r/^(in witness whereof|signature)/i
    ]
  ]

# Load .env file in development and test environments
if Mix.env() in [:dev, :test] do
  try do
    Dotenv.load()
  rescue
    _ -> :ok
  end
end

config :evhlegalchat,
  ecto_repos: [Evhlegalchat.Repo],
  generators: [timestamp_type: :utc_datetime]

# OpenRouter API configuration
# Set OPENROUTER_API_KEY environment variable or add to .env file
config :evhlegalchat, :openrouter,
  api_key: System.get_env("OPENROUTER_API_KEY"),
  base_url: "https://openrouter.ai/api/v1"

# Configures the endpoint
config :evhlegalchat, EvhlegalchatWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EvhlegalchatWeb.ErrorHTML, json: EvhlegalchatWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Evhlegalchat.PubSub

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :evhlegalchat, Evhlegalchat.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Mapping defaults (Step 6)
config :evhlegalchat, Evhlegalchat.Mapping.Config,
  auto_commit_threshold: 0.80,
  review_threshold: 0.60,
  allow_downgrade: false,
  prefer_newer_equal_conf: true,
  protected_columns: %{
    "agreements" => ~w(effective_date governing_law venue status review_status storage_key)a
  }

# CORS configuration
config :cors_plug,
  origin: ["https://evhlegal-front.onrender.com", "http://localhost:3000"],
  max_age: 86400,
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]

# Asset build tools
config :esbuild,
  version: "0.21.5",
  default: [
    args: ~w(js/app.js --bundle --target=es2020 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --external:phoenix --external:phoenix_html --external:phoenix_live_view),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "4.0.4",
  evhlegalchat: [
    args: ~w(
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]
# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"