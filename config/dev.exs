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

# Storage configuration for development
config :evhlegalchat, Evhlegalchat.Storage.Local,
  root: System.get_env("STORAGE_ROOT", "priv/storage")

# Antivirus scanning configuration (disabled by default in dev)
config :evhlegalchat, Evhlegalchat.Ingest.AV,
  enabled: false

# Oban configuration for background jobs
config :evhlegalchat, Oban,
  plugins: [Oban.Plugins.Pruner],
  queues: [ingest: 5],
  repo: Evhlegalchat.Repo

# Text extraction configuration
config :evhlegalchat, Evhlegalchat.Ingest.Extract,
  # Tool paths (fallback to system PATH if nil)
  pdftotext_path: System.get_env("PDFTOTEXT_PATH", "pdftotext"),
  pdftoppm_path: System.get_env("PDFTOPPM_PATH", "pdftoppm"),
  tesseract_path: System.get_env("TESSERACT_PATH", "tesseract"),
  pandoc_path: System.get_env("PANDOC_PATH", "pandoc"),
  libreoffice_path: System.get_env("LIBREOFFICE_PATH", "libreoffice"),
  pdfinfo_path: System.get_env("PDFINFO_PATH", "pdfinfo"),
  
  # Timeouts (milliseconds)
  timeout_per_page: 30_000,        # 30s per page for individual page operations
  timeout_per_file: 300_000,       # 5min total per file extraction
  
  # Limits
  max_pages: 1000,                 # Reject files with >1000 pages
  max_byte_size: 100_000_000,      # 100MB file size limit
  max_preview_pages: 10,           # Maximum preview images to generate
  
  # OCR thresholds
  ocr_char_threshold: 100,         # Minimum chars per page before engaging OCR
  ocr_nonprintable_threshold: 0.3 # 30% non-println chars threshold for OCR

# Segmentation configuration
config :evhlegalchat, Evhlegalchat.Segmentation,
  version: "seg-v1.0",
  min_boundary_gap: 80,
  overlap_window: 30,
  accept_threshold: 0.75,
  review_threshold: 0.40,
  min_boundaries_for_large_doc: 3,
  large_doc_pages: 5,
  ocr_low_conf_penalty: 0.20,
  min_unheaded_block_size: 500,
  min_clause_size: 50,
  max_short_clause_ratio: 0.3,
  max_low_conf_ratio: 0.25