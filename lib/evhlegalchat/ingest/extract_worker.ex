defmodule Evhlegalchat.Ingest.ExtractWorker do
  @moduledoc """
  Oban worker for extracting content from staged uploads.
  
  Implements Step 2 of the extraction pipeline with comprehensive text extraction,
  artifact storage, and Step 3 coordination.
  """

  use Oban.Worker, 
    queue: :ingest, 
    max_attempts: 10,
    unique: [fields: [:args], keys: [:staging_upload_id], period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  import Ecto.Query
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Ingest.{StagingUpload, Artifacts, Events}
  alias Evhlegalchat.Ingest.Extract.{PDF, DOCX, TXT, Metrics}
  alias Evhlegalchat.Storage.Local

  # Poison pill threshold
  @poison_pill_threshold 3

  @doc """
  Processes a staged upload through content extraction pipeline.
  """
  def perform(%Oban.Job{args: %{"staging_upload_id" => staging_upload_id}}) do
    Logger.metadata(staging_upload_id: staging_upload_id)

    :telemetry.span([:evhlegalchat, :ingest, :extraction], 
      %{staging_upload_id: staging_upload_id},
      fn ->
        result = do_extraction(staging_upload_id)
        
        measurements = case result do
          {:ok, {:extracted, metrics}} ->
            %{
              page_count: metrics["page_count"] || 0,
              char_count: metrics["char_count"] || 0,
              word_count: metrics["word_count"] || 0,
              ocr: metrics["ocr"] || false
            }
          _ ->
            %{duration: :timer.seconds(1)}
        end
        
        metadata = case result do
          {:ok, {:extracted, metrics}} ->
            %{staging_upload_id: staging_upload_id, ocr: metrics["ocr"], 
              language: metrics["language"], tools_used: metrics["tools_used"]}
          {:ok, {:already_extracted}} ->
            %{staging_upload_id: staging_upload_id, already_extracted: true}
          {:error, reason} ->
            %{staging_upload_id: staging_upload_id, error: reason}
          {status, reason} ->
            %{staging_upload_id: staging_upload_id, status: status, reason: reason}
        end
        
        {result, measurements, metadata}
      end
    )
  end

  # Main extraction pipeline

  defp do_extraction(staging_upload_id) do
    with {:ok, staging_upload} <- get_staging_upload(staging_upload_id),
         :ok <- validate_status(staging_upload),
         :ok <- check_blocklist(staging_upload),
         {:ok, {:already_extracted, _}} <- check_already_extracted(staging_upload) do
      {:ok, {:already_extracted}}
    else
      # Not already extracted, proceed with extraction
      {:ok, staging_upload} ->
        with :ok <- update_status_safely(staging_upload, :extracting),
             {:ok, temp_path} <- resolve_file_storage(staging_upload),
             {:ok, extract_result} <- extract_by_content_type(temp_path, staging_upload.content_type_detected),
             {:ok, artifacts} <- store_extraction_artifacts(staging_upload_id, extract_result),
             {:ok, metadata} <- update_staging_metadata(staging_upload_id, artifacts, extract_result),
             :ok <- enqueue_step3(staging_upload_id, artifacts["artifact_keys"], metadata) do
          
          Logger.info("Extraction completed successfully",
            staging_upload_id: staging_upload_id,
            page_count: extract_result.page_count,
            char_count: extract_result.char_count,
            ocr: extract_result.ocr or false
          )
          
          {:ok, {:extracted, metadata}}
        else
          {:error, :unsupported_mime} ->
            update_status_with_rejection(staging_upload_id, "unsupported_mime")
            {:discard, :unsupported_mime}
          
          {:error, :file_too_large} ->
            update_status_with_rejection(staging_upload_id, "file_too_large")
            {:discard, :file_too_large}
          
          {:error, {:too_many_pages, page_count}} ->
            update_status_with_rejection(staging_upload_id, "too_many_pages:#{page_count}")
            {:discard, {:too_many_pages, page_count}}
          
          {:error, {:tool_missing, tools}} ->
            Logger.error("Required extraction tools missing", 
              staging_upload_id: staging_upload_id, 
              missing: tools
            )
            update_status_with_rejection(staging_upload_id, "tool_missing:#{Enum.join(tools, ",")}")
            {:discard, {:tool_missing, tools}}
          
          error ->
            Logger.error("Extraction failed", 
              staging_upload_id: staging_upload_id, 
              error: error
            )
            
            case check_poison_pill(staging_upload_id, staging_upload) do
              :block ->
                _ = Evhlegalchat.Events.emit("extraction.gap.detected", %{staging_upload_id: staging_upload_id, reason: inspect(error)})
                Events.publish_extraction_blocked(
                  staging_upload_id, 
                  staging_upload.source_hash, 
                  get_attempt_count(staging_upload_id),
                  "extraction_unstable"
                )
                update_status_with_rejection(staging_upload_id, "extraction_unstable")
                {:discard, :extraction_unstable}
              
              :retry ->
                update_status_safely(staging_upload, :error)
                Events.publish_extraction_failure(staging_upload_id, error, %{})
                {:error, error}
            end
        end
      
      error ->
        Logger.error("Extraction pipeline failed", 
          staging_upload_id: staging_upload_id, 
          error: error
        )
        {:error, error}
    end
  end

  # Database operations

  defp get_staging_upload(staging_upload_id) do
    case Repo.get(StagingUpload, staging_upload_id) do
      nil -> {:error, :not_found}
      staging_upload -> {:ok, staging_upload}
    end
  end

  defp validate_status(%StagingUpload{status: status}) do
    if status in [:ready_for_extraction, :extracting] do
      :ok
    else
      {:error, :invalid_status}
    end
  end

  defp update_status_safely(staging_upload, new_status) do
    staging_upload
    |> StagingUpload.changeset(%{status: new_status})
    |> Repo.update()
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp update_status_with_rejection(staging_upload_id, reason) do
    from(s in StagingUpload, where: s.staging_upload_id == ^staging_upload_id)
    |> Repo.update_all(set: [
      status: :rejected,
      rejection_reason: reason,
      updated_at: DateTime.utc_now()
    ])
    |> case do
      {1, _} -> :ok
      _ -> {:error, :update_failed}
    end
  end

  # Blocklist and poison pill logic

  defp check_blocklist(%StagingUpload{source_hash: source_hash}) do
    if Events.blocked?(source_hash) do
      {:error, :blocked}
    else
      :ok
    end
  end

  defp check_poison_pill(staging_upload_id, %StagingUpload{source_hash: source_hash}) do
    attempt_count = get_attempt_count(staging_upload_id)
    
    if attempt_count >= @poison_pill_threshold do
      :block
    else
      :retry
    end
  end

  defp get_attempt_count(staging_upload_id) do
    # Count failed attempts for this staging upload
    from(j in Oban.Job,
      where: j.args["staging_upload_id"] == ^staging_upload_id,
      where: j.state in [:retryable, :failed, :cancelled]
    )
    |> Repo.aggregate(:count)
  end

  # Idempotency check

  defp check_already_extracted(staging_upload) do
    case staging_upload.metadata do
      %{"artifact_keys" => artifact_keys} when not is_nil(artifact_keys) ->
        if Artifacts.validate_artifacts(staging_upload.staging_upload_id, artifact_keys) do
          # Artifacts exist and are valid, skip extraction and enqueue Step 3
          enqueue_step3_from_existing(staging_upload)
          {:ok, {:already_extracted, artifact_keys}}
        else
          # Invalid artifacts, need to re-extract
          {:ok, :needs_extraction}
        end
      _ ->
        {:ok, :needs_extraction}
    end
  end

  # File resolution

  defp resolve_file_storage(staging_upload) do
    storage = Local.new()
    
    case Local.get(storage, staging_upload.storage_key) do
      {:ok, file_path} ->
        {:ok, file_path}
      {:error, :not_found} ->
        Logger.error("File not found in storage", 
          staging_upload_id: staging_upload.staging_upload_id,
          storage_key: staging_upload.storage_key
        )
        {:error, :file_not_found}
      {:error, reason} ->
        Logger.error("Storage resolution failed", 
          staging_upload_id: staging_upload.staging_upload_id,
          reason: reason
        )
        {:error, reason}
    end
  end

  # Content type extraction routing

  defp extract_by_content_type(file_path, content_type) do
    temp_dir = System.tmp_dir!()
    
    case content_type do
      "application/pdf" ->
        extract_with_timeout(PDF, :extract, [file_path, temp_dir])
      
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ->
        extract_with_timeout(DOCX, :extract, [file_path, temp_dir])
      
      "text/plain" ->
        extract_with_timeout(TXT, :extract, [file_path, temp_dir])
      
      _ ->
        Logger.warning("Unsupported content type", content_type: content_type)
        {:error, :unsupported_mime}
    end
  end

  defp extract_with_timeout(module, function, args) do
    extract_config = Application.get_env(:evhlegalchat, Evhlegalchat.Ingest.Extract, [])
    timeout = Keyword.get(extract_config, :timeout_per_file, 300_000)

    Task.async(fn -> apply(module, function, args) end)
    |> Task.await(timeout)
  rescue
    e in Task.TimeoutError ->
      Logger.error("Extraction timeout", module: module)
      {:error, :timeout}
  end

  # Artifact storage

  defp store_extraction_artifacts(staging_upload_id, extract_result) do
    temp_dir = System.tmp_dir!()
    artifacts_temp_dir = Path.join(temp_dir, "artifacts_#{staging_upload_id}")
    File.mkdir_p!(artifacts_temp_dir)

    try do
      with {:ok, text_concat_key} <- store_text_concat(staging_upload_id, extract_result.text, artifacts_temp_dir),
           {:ok, pages_jsonl_key} <- store_pages_jsonl(staging_upload_id, extract_result.pages, artifacts_temp_dir),
           {:ok, metrics_key} <- store_metrics(staging_upload_id, extract_result, artifacts_temp_dir),
           {:ok, preview_keys} <- store_previews(staging_upload_id, extract_result, artifacts_temp_dir) do
        
        artifact_keys = %{
          "text_concat" => text_concat_key,
          "pages_jsonl" => pages_jsonl_key,
          "metrics" => metrics_key
        } |> Map.merge(preview_keys)
        
        {:ok, %{"artifact_keys" => Artifacts.clean_artifact_keys(artifact_keys)}}
      end
    after
      File.rm_rf(artifacts_temp_dir)
    end
  end

  defp store_text_concat(staging_upload_id, text, artifacts_temp_dir) do
    text_file = Path.join(artifacts_temp_dir, "concatenated.txt")
    File.write!(text_file, text)
    
    storage_key = Artifacts.build_artifact_key(staging_upload_id, :text_concat)
    
    with :ok <- Artifacts.upload_artifact(storage_key, text_file) do
      Events.publish_artifact_stored(staging_upload_id, :text_concat, storage_key, byte_size(text))
      {:ok, storage_key}
    end
  end

  defp store_pages_jsonl(staging_upload_id, pages, artifacts_temp_dir) do
    pages_jsonl = pages
    |> Enum.map(&Jason.encode!(&1))
    |> Enum.join("\n")
    
    pages_file = Path.join(artifacts_temp_dir, "pages.jsonl")
    File.write!(pages_file, pages_jsonl)
    
    storage_key = Artifacts.build_artifact_key(staging_upload_id, :pages_jsonl)
    
    with :ok <- Artifacts.upload_artifact(storage_key, pages_file) do
      {:ok, storage_key}
    end
  end

  defp store_metrics(staging_upload_id, extract_result, artifacts_temp_dir) do
    metrics = Metrics.compute_metrics(extract_result, 
      include_previews: extract_result.previews_generated,
      preview_page_count: if(extract_result.previews_generated, do: min(extract_result.page_count, 10), else: 0)
    )
    
    metrics_json = Jason.encode!(metrics)
    metrics_file = Path.join(artifacts_temp_dir, "metrics.json")
    File.write!(metrics_file, metrics_json)
    
    storage_key = Artifacts.build_artifact_key(staging_upload_id, :metrics)
    
    with :ok <- Artifacts.upload_artifact(storage_key, metrics_file) do
      {:ok, storage_key}
    end
  end

  defp store_previews(staging_upload_id, extract_result, artifacts_temp_dir) do
    if extract_result.previews_generated do
      preview_keys = generate_and_store_previews(staging_upload_id, artifacts_temp_dir)
      {:ok, preview_keys}
    else
      {:ok, %{}}
    end
  end

  defp generate_and_store_previews(staging_upload_id, artifacts_temp_dir) do
    # This would integrate with the preview generation from PDF extraction
    # For now, return empty preview keys
    %{"previews_prefix" => Artifacts.build_artifact_key(staging_upload_id, :previews)}
  end

  # Metadata updates

  defp update_staging_metadata(staging_upload_id, artifacts, extract_result) do
    quality_signals = Metrics.quality_signals(extract_result)
    
    metadata_updates = Map.merge(artifacts, %{
      "page_count" => extract_result.page_count,
      "char_count" => extract_result.char_count,
      "word_count" => extract_result.word_count,
      "ocr" => extract_result.ocr,
      "extracted_at" => DateTime.utc_now(),
      "quality_signals" => quality_signals
    })
    
    # Add OCR confidence if OCR was used
    metadata_updates = if extract_result.ocr do
      Map.put(metadata_updates, "ocr_confidence", extract_result.ocr_confidence)
    else
      metadata_updates
    end
    
    metadata_updates = Map.merge(metadata_updates, extract_result.tools_used, fn 
      "tools_used", _, val -> val
      _, _, val -> val
    end)

    update_query = from(s in StagingUpload, where: s.staging_upload_id == ^staging_upload_id)
    
    case Repo.update_all(update_query, set: [
      metadata: metadata_updates,
      status: :extracted,
      updated_at: DateTime.utc_now()
    ]) do
      {1, _} -> {:ok, metadata_updates}
      _ -> {:error, :update_failed}
    end
  end

  # Step 3 coordination

  defp enqueue_step3(staging_upload_id, artifact_keys, metadata) do
    Events.publish_extraction_ready(staging_upload_id, artifact_keys, metadata)
    :ok
  end

  defp enqueue_step3_from_existing(staging_upload) do
    metadata = staging_upload.metadata
    artifact_keys = Map.get(metadata, "artifact_keys", %{})
    
    Events.publish_extraction_ready(staging_upload.staging_upload_id, artifact_keys, metadata)
    :ok
  end
end