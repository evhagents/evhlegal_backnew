defmodule EvhlegalchatWeb.Plugs.NdaProcessor do
  @moduledoc """
  Phoenix plug for processing NDA documents during upload.
  Integrates with LiveView upload process to automatically parse and store NDA content.
  """

  alias Evhlegalchat.Nda.Ingestion

  require Logger

  @doc """
  Processes NDA documents from upload entries.

  This plug can be used in LiveView upload callbacks to automatically
  process NDA documents and extract structured information.
  """
  def process_nda_upload(entry, temp_path, opts \\ []) do
    case is_nda_document?(entry) do
      true ->
        Logger.info("Processing NDA document: #{entry.client_name}")
        process_document_async(entry, temp_path, opts)

      false ->
        Logger.debug("Skipping non-NDA document: #{entry.client_name}")
        {:ok, :skipped}
    end
  end

  defp is_nda_document?(entry) do
    filename = String.downcase(entry.client_name)

    # Check if filename contains NDA-related keywords
    nda_keywords = ["nda", "non-disclosure", "confidentiality", "secrecy"]

    Enum.any?(nda_keywords, fn keyword ->
      String.contains?(filename, keyword)
    end) or has_supported_extension?(filename)
  end

  defp has_supported_extension?(filename) do
    ext = Path.extname(filename)
    ext in [".pdf", ".txt", ".docx"]
  end

  defp process_document_async(entry, temp_path, opts) do
    # Process in a task to avoid blocking the upload
    Task.start(fn ->
      case Ingestion.process_document(entry, temp_path, Map.new(opts)) do
        {:ok, nda_anatomy} ->
          Logger.info("Successfully processed NDA: #{nda_anatomy.id}")
          broadcast_processing_complete(nda_anatomy)

        {:error, reason} ->
          Logger.error("Failed to process NDA #{entry.client_name}: #{reason}")
          broadcast_processing_error(entry, reason)
      end
    end)

    {:ok, :processing}
  end

  defp broadcast_processing_complete(nda_anatomy) do
    Phoenix.PubSub.broadcast(
      Evhlegalchat.PubSub,
      "nda_processing",
      {:nda_processed, nda_anatomy}
    )
  end

  defp broadcast_processing_error(entry, reason) do
    Phoenix.PubSub.broadcast(
      Evhlegalchat.PubSub,
      "nda_processing",
      {:nda_error, entry.client_name, reason}
    )
  end

  @doc """
  Phoenix plug init function.
  """
  def init(opts), do: opts

  @doc """
  Phoenix plug call function.
  This can be used in the router or controller pipeline if needed.
  """
  def call(conn, _opts) do
    # This plug is primarily designed for LiveView upload integration
    # but can be extended for regular HTTP uploads if needed
    conn
  end
end
