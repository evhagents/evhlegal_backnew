defmodule EvhlegalchatWeb.ReviewController do
  use EvhlegalchatWeb, :controller

  alias Evhlegalchat.Mapping.Review

  def resolve(conn, %{"id" => id, "decision" => decision} = params) do
    actor_user_id = Map.get(params, "actor_user_id")
    resolution = Map.get(params, "resolution")

    decision_atom =
      case decision do
        "approve" -> :approve
        "reject" -> :reject
        _ -> :reject
      end

    case Review.resolve_task!(String.to_integer(id), decision_atom, %{actor_user_id: actor_user_id, resolution: resolution}) do
      {:ok, task} -> json(conn, %{status: "ok", task_id: task.review_task_id})
      {:error, reason} -> conn |> put_status(:unprocessable_entity) |> json(%{status: "error", reason: inspect(reason)})
    end
  end
end


