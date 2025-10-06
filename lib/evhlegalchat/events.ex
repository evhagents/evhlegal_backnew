defmodule Evhlegalchat.Events do
  @moduledoc """
  Domain event emitter. Publishes via Phoenix.PubSub and Telemetry.

  Subscribers can:
  - subscribe to topic: "domain_events" for PubSub messages {:domain_event, event_name, metadata}
  - attach Telemetry handlers to e.g. [:agreement, :created]
  """

  @pubsub Evhlegalchat.PubSub

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, "domain_events")
  end

  @spec emit(String.t(), map()) :: :ok
  def emit(event_name, metadata) when is_binary(event_name) and is_map(metadata) do
    Phoenix.PubSub.broadcast(@pubsub, "domain_events", {:domain_event, event_name, metadata})

    telemetry_event =
      event_name
      |> String.split(".")
      |> Enum.map(&String.to_atom/1)

    :telemetry.execute(telemetry_event, %{count: 1}, metadata)
    :ok
  end
end


