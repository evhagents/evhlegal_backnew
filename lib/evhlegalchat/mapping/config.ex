defmodule Evhlegalchat.Mapping.Config do
  @moduledoc false

  @defaults [
    auto_commit_threshold: 0.80,
    review_threshold: 0.60,
    allow_downgrade: false,
    prefer_newer_equal_conf: true,
    protected_columns: %{
      "agreements" => ~w(effective_date governing_law venue status review_status storage_key)a
    }
  ]

  def fetch do
    app = :evhlegalchat
    mod = __MODULE__
    opts = Application.get_env(app, mod, [])
    Keyword.merge(@defaults, opts)
  end
end



