defmodule EvhlegalchatWeb.StagingUploadLive do
  @moduledoc """
  LiveView for uploading and managing staging files.
  
  Provides a file upload interface with progress tracking and
  deduplication feedback.
  """

  use EvhlegalchatWeb, :live_view
  require Logger
  alias Evhlegalchat.Ingest.{StagingService, StagingUpload}

  @max_file_size 10_000_000  # 10MB
  @allowed_extensions ~w(.pdf .docx .txt)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :ok = :telemetry.attach_many(
        "staging_upload_telemetry",
        [
          [:evhlegalchat, :ingest, :upload_staged],
          [:evhlegalchat, :ingest, :upload_duplicate_detected]
        ],
        &handle_telemetry_event/4,
        nil
      )
    end

    socket =
      socket
      |> assign(:uploads, [])
      |> assign(:staging_uploads, [])
      |> assign(:current_scope, "staging_upload")
      |> allow_upload(:docs, accept: @allowed_extensions, max_file_size: @max_file_size, auto_upload: true)

    {:ok, socket}
  end

  @impl true
  def handle_progress(event, entry, socket) do
    Logger.info("Upload progress for #{entry.client_name}: #{event}")
    socket =
      cond do
        entry.done? ->
          handle_upload_complete(entry, socket)
        event == :progress ->
          socket
        true ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    cancelled_uploads = consume_uploaded_entries(socket, :docs, fn %{ref: ^ref}, _entry -> {:ok, :cancelled} end)
    {:noreply, assign(socket, :uploads, socket.assigns.uploads -- cancelled_uploads)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    staging_uploads = StagingService.list_staging_uploads(limit: 20)
    {:noreply, assign(socket, :staging_uploads, staging_uploads)}
  end

  @impl true
  def handle_info({:telemetry_event, event_name, measurements, metadata}, socket) do
    Logger.info("Telemetry event: #{event_name}")
    
    # Refresh staging uploads list on relevant events
    if event_name in [:upload_staged, :upload_duplicate_detected] do
      staging_uploads = StagingService.list_staging_uploads(limit: 20)
      {:noreply, assign(socket, :staging_uploads, staging_uploads)}
    else
      {:noreply, socket}
    end
  end

  # Private functions

  defp handle_upload_complete(entry, socket) do
    Logger.info("Processing complete upload: #{entry.client_name}")

    consume_uploaded_entries(socket, :docs, fn %{path: path}, entry ->
      process_uploaded_file(path, entry, socket)
      {:ok, path}
    end)

    socket
  end

  defp process_uploaded_file(temp_file, entry, socket) do
    original_filename = entry.client_name
    Logger.metadata(filename: original_filename)

    case StagingService.stage_upload(temp_file, original_filename) do
      {:ok, staging_upload} ->
        Logger.info("File staged successfully: #{staging_upload.source_hash}")
        
        # Refresh the staging uploads list
        staging_uploads = StagingService.list_staging_uploads(limit: 20)
        send(self(), {:refresh_staging_uploads, staging_uploads})
        
      {:error, reason} ->
        Logger.error("Failed to stage file: #{inspect(reason)}")
        
        send(self(), {:upload_error, original_filename, reason})
    end
  end

  defp handle_telemetry_event([:evhlegalchat, :ingest, event_name], measurements, metadata, _config) do
    send(self(), {:telemetry_event, event_name, measurements, metadata})
  end

  @impl true
  def handle_info({:refresh_staging_uploads, staging_uploads}, socket) do
    {:noreply, assign(socket, :staging_uploads, staging_uploads)}
  end

  @impl true
  def handle_info({:upload_error, filename, reason}, socket) do
    # Handle error display in UI
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} page_title="File Staging">
      <div class="container mx-auto px-4 py-8">
        <h1 class="text-3xl font-bold text-gray-900 mb-8">File Upload & Staging</h1>

        <!-- Upload Form -->
        <div class="bg-white rounded-lg shadow-md p-6 mb-8">
          <h2 class="text-xl font-semibold text-gray-800 mb-4">Upload Documents</h2>
          
          <form phx-submit="save" phx-change="validate">
            <.live_file_input upload={@uploads.docs} required />
            
            <div phx-drop-target={@uploads.docs.ref} class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center hover:border-blue-400 transition-colors">
              <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
                <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8H32 20v-8m0-8h-8l-8 8h8l4-4z" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
              <p class="mt-2 text-sm text-gray-600">
                Drop PDF, DOCX, or TXT files here, or <span class="text-blue-600 hover:text-blue-500 cursor-pointer">click to browse</span>
              </p>
              <p class="mt-1 text-xs text-gray-500">Maximum file size: 10MB</p>
            </div>

            <div :for={entry <- @uploads.docs.entries} class="mt-4 p-4 bg-gray-50 rounded-lg">
              <div class="flex items-center justify-between">
                <div>
                  <span class="text-sm font-medium text-gray-900">{entry.client_name}</span>
                  <span class="text-xs text-gray-500">({entry.client_size_humanized})</span>
                </div>
                <button
                  type="button"
                  phx-click="cancel_upload"
                  phx-value-ref={entry.ref}
                  class="text-red-600 hover:text-red-700 text-sm"
                >
                  Remove
                </button>
              </div>
              
              <div :if={entry.progress > 0} class="mt-2">
                <div class="bg-gray-200 rounded-full h-2">
                  <div class="bg-blue-600 h-2 rounded-full transition-all duration-300" style={"width: #{entry.progress}%"}></div>
                </div>
                <p class="text-xs text-gray-500 mt-1">{entry.progress}% complete</p>
              </div>
            </div>
          </form>
        </div>

        <!-- Staging Uploads List -->
        <div class="bg-white rounded-lg shadow-md p-6">
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-semibold text-gray-800">Staging Uploads</h2>
            <button phx-click="refresh" class="text-blue-600 hover:text-blue-700 text-sm font-medium">
              Refresh
            </button>
          </div>

          <div :if={@staging_uploads == []} class="text-center py-8 text-gray-500">
            No staging uploads yet. Upload some files to get started.
          </div>

          <div :if={@staging_uploads != []} class="space-y-4">
            <div :for={upload <- @staging_uploads} class="border border-gray-200 rounded-lg p-4">
              <div class="flex items-center justify-between">
                <div class="flex-1">
                  <h3 class="font-medium text-gray-900">{upload.original_filename}</h3>
                  <div class="flex items-center space-x-4 mt-1 text-sm text-gray-500">
                    <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
                      {StagingUpload.status_description(upload)}
                    </span>
                    <span>Hash: {String.slice(upload.source_hash, 0, 8)}...</span>
                    <span>{upload.byte_size |> humanize_size()}</span>
                  </div>
                </div>
                <div class="text-sm text-gray-500">
                  {format_relative_time(upload.inserted_at)}
                </div>
              </div>
              
              <div :if={upload.rejection_reason} class="mt-2 text-sm text-red-600">
                Rejected: {upload.rejection_reason}
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp humanize_size(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{round(bytes / 1024)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{round(bytes / (1024 * 1024))} MB"
      true -> "#{round(bytes / (1024 * 1024 * 1024))} GB"
    end
  end

  defp format_relative_time(naive_datetime) do
    # Simple relative time formatting
    hours_ago = div(System.os_time(:second) - DateTime.to_unix(naive_datetime), 3600)
    
    cond do
      hours_ago < 1 -> "just now"
      hours_ago < 24 -> "#{hours_ago} hours ago"
      true -> "#{div(hours_ago, 24)} days ago"
    end
  end
end
