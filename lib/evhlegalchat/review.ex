defmodule Evhlegalchat.Review do
  @moduledoc """
  Simple review flagging helper.
  """
  require Logger
  alias Evhlegalchat.Repo

  def flag!(agreement_id, entity, reason, evidence_clause_id, details) do
    attrs = %{
      agreement_id: agreement_id,
      entity: to_string(entity),
      reason: to_string(reason),
      evidence_clause_id: evidence_clause_id,
      details: details || %{}
    }

    %Ecto.Changeset{data: %{}}
    |> Ecto.Changeset.cast(attrs, [:agreement_id, :entity, :reason, :evidence_clause_id, :details])
    |> Repo.insert!(
      source: {nil, "review_flags"},
      on_conflict: :nothing,
      conflict_target: [:agreement_id, :entity, :reason, :evidence_clause_id]
    )

    :telemetry.execute([:enrich, :review, :flagged], %{count: 1}, Map.put(attrs, :timestamp, DateTime.utc_now()))
    :ok
  end
end


