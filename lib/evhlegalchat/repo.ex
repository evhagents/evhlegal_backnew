defmodule Evhlegalchat.Repo do
  use Ecto.Repo,
    otp_app: :evhlegalchat,
    adapter: Ecto.Adapters.Postgres
end
