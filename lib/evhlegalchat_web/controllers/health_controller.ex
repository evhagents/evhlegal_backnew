defmodule EvhlegalchatWeb.HealthController do
  use EvhlegalchatWeb, :controller

  def health(conn, _params) do
    json(conn, %{
      status: "ok",
      timestamp: DateTime.utc_now(),
      service: "evhlegal-backend",
      version: "0.1.0"
    })
  end
end
