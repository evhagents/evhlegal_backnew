defmodule EvhlegalchatWeb.ReviewTasksLive do
  use EvhlegalchatWeb, :live_view
  import Ecto.Query
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Mapping.ReviewTask
  alias Evhlegalchat.Mapping.Review

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
      socket
      |> assign(:current_scope, "reviews")
      |> assign(:tasks, list_open_tasks())}
  end

  defp list_open_tasks() do
    from(r in ReviewTask, where: r.state in [^:open, ^:in_progress], order_by: [desc: r.inserted_at])
    |> Repo.all()
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    _ = Review.resolve_task!(String.to_integer(id), :approve, %{})
    {:noreply, assign(socket, :tasks, list_open_tasks())}
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    _ = Review.resolve_task!(String.to_integer(id), :reject, %{})
    {:noreply, assign(socket, :tasks, list_open_tasks())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title="Review Tasks">
      <div class="max-w-5xl mx-auto px-4 py-8">
        <h1 class="text-2xl font-semibold mb-6">Open Review Tasks</h1>

        <div :if={@tasks == []} class="text-gray-500">No open tasks 🎉</div>

        <div :for={{agreement_id, items} <- group_tasks(@tasks)} class="mb-8">
          <div class="flex items-center justify-between mb-2">
            <h2 class="text-lg font-medium text-gray-900">Agreement #{agreement_id}</h2>
            <div class="text-sm text-gray-500">{length(items)} pending</div>
          </div>

          <div class="space-y-3">
            <div :for={task <- items} class="bg-white rounded-lg shadow p-4">
              <div class="flex items-start justify-between gap-4">
                <div class="flex-1">
                  <div class="font-medium text-gray-900">{task.title}</div>
                  <div class="mt-1 text-sm text-gray-600">
                    <%= with details <- task.details || %{},
                            tgt <- details["target"] || %{},
                            prop <- details["proposal"] || %{},
                            table <- friendly_table_name(tgt["table"]),
                            column <- friendly_column_label(tgt["table"], tgt["column"]),
                            value <- prop["normalized"] || prop["raw"],
                            conf <- prop["confidence"] do %>
                      <span class="inline-flex items-center gap-2">
                        <span class="text-gray-700">{table}</span>
                        <span class="text-gray-400">/</span>
                        <span class="text-gray-700">{column}</span>
                        <span class="text-gray-400">→</span>
                        <span class="text-gray-900 font-medium">{value}</span>
                        <span :if={conf} class="ml-2 text-xs px-2 py-0.5 rounded-full bg-blue-50 text-blue-700">{confidence_text(conf)}</span>
                      </span>
                    <% end %>
                  </div>
                </div>
                <div class="flex items-center gap-2 shrink-0">
                  <button phx-click="approve" phx-value-id={task.review_task_id} class="px-3 py-1 rounded bg-emerald-600 hover:bg-emerald-700 text-white text-sm">Approve</button>
                  <button phx-click="reject" phx-value-id={task.review_task_id} class="px-3 py-1 rounded bg-red-600 hover:bg-red-700 text-white text-sm">Reject</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ——— Helpers for grouping and labels ———
  defp group_tasks(tasks) do
    tasks
    |> Enum.group_by(& &1.agreement_id)
    |> Enum.sort_by(fn {agreement_id, _} -> agreement_id end)
  end

  defp friendly_table_name("agreements"), do: "Agreement"
  defp friendly_table_name("sow_deliverables"), do: "SOW / Deliverables"
  defp friendly_table_name("sow_milestones"), do: "SOW / Milestones"
  defp friendly_table_name("sow_pricing_schedules"), do: "SOW / Pricing"
  defp friendly_table_name("sow_rate_cards"), do: "SOW / Rate Cards"
  defp friendly_table_name("sow_invoicing_terms"), do: "SOW / Invoicing"
  defp friendly_table_name(other) when is_binary(other), do: other
  defp friendly_table_name(_), do: ""

  defp friendly_column_label("agreements", col), do: titleize(col)
  defp friendly_column_label(_, col), do: titleize(col)

  defp titleize(nil), do: ""
  defp titleize(col) when is_binary(col) do
    col
    |> String.replace("_", " ")
    |> String.capitalize()
  end
  defp titleize(col), do: to_string(col)

  defp confidence_text(nil), do: nil
  defp confidence_text(%Decimal{} = d) do
    float = Decimal.to_float(d) * 100.0
    to_string(Float.round(float, 1)) <> "%"
  end
  defp confidence_text(conf) when is_number(conf) do
    to_string(Float.round(conf * 100.0, 1)) <> "%"
  end
end


