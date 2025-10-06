defmodule Evhlegalchat.Ingest.SegmentWorker do
  @moduledoc """
  Oban worker for document segmentation.
  
  Processes extracted text artifacts to identify clause boundaries
  and create structured segmentation results.
  """

  use Oban.Worker, 
    queue: :ingest, 
    max_attempts: 10,
    unique: [fields: [:args], keys: [:staging_upload_id, :segmentation_version], period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  import Ecto.Query
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Ingest.{StagingUpload, Artifacts}
  alias Evhlegalchat.Segmentation

  @doc """
  Processes a staging upload through segmentation.
  """
  def perform(%Oban.Job{args: %{
    "staging_upload_id" => staging_upload_id,
    "artifact_keys" => artifact_keys,
    "segmentation_version" => segmentation_version
  }}) do
    Logger.metadata(staging_upload_id: staging_upload_id, segmentation_version: segmentation_version)

    :telemetry.span([:evhlegalchat, :segmentation], 
      %{staging_upload_id: staging_upload_id, segmentation_version: segmentation_version},
      fn ->
        result = do_segmentation(staging_upload_id, artifact_keys, segmentation_version)
        
        measurements = case result do
          {:ok, :completed, metrics} ->
            %{
              accepted_count: metrics.accepted_count,
              suppressed_count: metrics.suppressed_count,
              mean_conf_boundary: metrics.mean_conf_boundary
            }
          {:ok, :needs_review, _metrics} ->
            %{needs_review: true}
          _ ->
            %{duration: :timer.seconds(1)}
        end
        
        metadata = case result do
          {:ok, :completed, metrics} ->
            %{staging_upload_id: staging_upload_id, completed: true, metrics: metrics}
          {:ok, :needs_review, metrics} ->
            %{staging_upload_id: staging_upload_id, needs_review: true, metrics: metrics}
          {:error, reason} ->
            %{staging_upload_id: staging_upload_id, error: reason}
        end
        
        {result, measurements, metadata}
      end
    )
  end

  # Main segmentation pipeline

  defp do_segmentation(staging_upload_id, artifact_keys, segmentation_version) do
    with {:ok, staging_upload} <- get_staging_upload(staging_upload_id),
         :ok <- validate_staging_status(staging_upload),
         :ok <- acquire_advisory_lock(staging_upload_id),
         {:ok, :not_duplicate} <- check_duplicate_run(staging_upload_id, segmentation_version),
         {:ok, artifacts} <- verify_artifacts(artifact_keys),
         {:ok, segmentation_run} <- create_segmentation_run(staging_upload_id, segmentation_version, artifact_keys),
         {:ok, seg_result} <- run_segmentation(artifacts, staging_upload),
         :ok <- process_segmentation_result(segmentation_run, seg_result, staging_upload_id) do
      
      Logger.info("Segmentation completed successfully",
        staging_upload_id: staging_upload_id,
        clause_count: length(seg_result.clauses),
        needs_review: seg_result.needs_review
      )
      
      {:ok, if(seg_result.needs_review, do: :needs_review, else: :completed), seg_result.metrics}
    else
      {:error, :missing_artifacts} ->
        Logger.error("Required artifacts missing", staging_upload_id: staging_upload_id)
        {:discard, :missing_artifacts}
      
      {:error, :duplicate_run} ->
        Logger.info("Duplicate segmentation run detected", staging_upload_id: staging_upload_id)
        {:ok, :already_completed}
      
      error ->
        Logger.error("Segmentation failed", 
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

  defp validate_staging_status(%StagingUpload{status: status}) do
    if status in [:extracted, :ready_for_extraction] do
      :ok
    else
      {:error, :invalid_status}
    end
  end

  defp acquire_advisory_lock(staging_upload_id) do
    # Use PostgreSQL advisory lock to prevent concurrent processing
    case Repo.query("SELECT pg_advisory_xact_lock($1)", [staging_upload_id]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_duplicate_run(staging_upload_id, segmentation_version) do
    # Check if a segmentation run already exists for this version
    query = from(sr in "segmentation_runs",
      where: sr.staging_upload_id == ^staging_upload_id,
      where: sr.segmentation_version == ^segmentation_version,
      where: sr.status in ["completed", "needs_review"]
    )
    
    case Repo.one(query) do
      nil -> {:ok, :not_duplicate}
      _existing -> {:error, :duplicate_run}
    end
  end

  defp verify_artifacts(artifact_keys) do
    required_artifacts = ["text_concat", "metrics"]
    
    missing_artifacts = Enum.filter(required_artifacts, fn key ->
      storage_key = Map.get(artifact_keys, key)
      not Artifacts.artifact_exists?(storage_key)
    end)
    
    if missing_artifacts == [] do
      {:ok, artifact_keys}
    else
      Logger.error("Missing required artifacts", missing: missing_artifacts)
      {:error, :missing_artifacts}
    end
  end

  defp create_segmentation_run(staging_upload_id, segmentation_version, artifact_keys) do
    # Parse version components
    {major, minor, patch} = parse_segmentation_version(segmentation_version)
    
    run_data = %{
      staging_upload_id: staging_upload_id,
      segmentation_major: major,
      segmentation_minor: minor,
      segmentation_patch: patch,
      segmentation_version: segmentation_version,
      status: "started",
      text_concat_key: artifact_keys["text_concat"],
      pages_jsonl_key: artifact_keys["pages_jsonl"]
    }
    
    case Repo.insert_all("segmentation_runs", [run_data], returning: [:segmentation_run_id]) do
      {1, [%{segmentation_run_id: run_id}]} ->
        {:ok, %{segmentation_run_id: run_id, staging_upload_id: staging_upload_id}}
      error ->
        Logger.error("Failed to create segmentation run", error: error)
        {:error, :insert_failed}
    end
  end

  defp run_segmentation(artifact_keys, staging_upload) do
    with {:ok, concat_text} <- load_concat_text(artifact_keys["text_concat"]),
         {:ok, pages} <- load_pages_data(artifact_keys["pages_jsonl"]),
         {:ok, metrics} <- load_extraction_metrics(artifact_keys["metrics"]) do
      
      # Prepare segmentation options
      opts = [
        segmentation_version: "seg-v1.0",
        ocr_used: Map.get(staging_upload.metadata, "ocr", false),
        ocr_confidence: Map.get(staging_upload.metadata, "ocr_confidence", 1.0)
      ]
      
      # Run segmentation
      seg_result = Segmentation.run(concat_text, pages, opts)
      
      {:ok, seg_result}
    else
      error ->
        Logger.error("Failed to load artifacts", error: error)
        {:error, error}
    end
  end

  defp process_segmentation_result(segmentation_run, seg_result, staging_upload_id) do
    if seg_result.needs_review do
      process_needs_review(segmentation_run, seg_result, staging_upload_id)
    else
      process_completed(segmentation_run, seg_result, staging_upload_id)
    end
  end

  defp process_needs_review(segmentation_run, seg_result, staging_upload_id) do
    # Update run status to needs_review
    update_run_status(segmentation_run.segmentation_run_id, "needs_review")
    
    # Store preview artifact
    preview_data = %{
      candidates: seg_result.clauses,
      anomalies: seg_result.anomalies,
      reasons: ["Low confidence boundaries", "Sparse segmentation", "OCR quality issues"]
    }
    
    preview_key = "staging/#{staging_upload_id}/segments/preview.json"
    store_preview_artifact(preview_key, preview_data)
    
    # Store events
    store_segmentation_events(segmentation_run.segmentation_run_id, seg_result.events)
    
    Logger.info("Segmentation marked for review",
      staging_upload_id: staging_upload_id,
      anomaly_count: length(seg_result.anomalies)
    )
    
    :ok
  end

  defp process_completed(segmentation_run, seg_result, staging_upload_id) do
    # Insert clauses
    insert_clauses(segmentation_run.segmentation_run_id, staging_upload_id, seg_result.clauses)
    
    # Update run with completion data
    update_run_completion(segmentation_run.segmentation_run_id, seg_result)
    
    # Store events
    store_segmentation_events(segmentation_run.segmentation_run_id, seg_result.events)
    
    # Optionally store clauses artifact
    clauses_key = "staging/#{staging_upload_id}/segments/clauses.jsonl"
    store_clauses_artifact(clauses_key, seg_result.clauses)
    
    Logger.info("Segmentation completed",
      staging_upload_id: staging_upload_id,
      clause_count: length(seg_result.clauses)
    )
    
    :ok
  end

  # Artifact loading functions

  defp load_concat_text(storage_key) do
    case Artifacts.download_artifact(storage_key) do
      {:ok, file_path} ->
        case File.read(file_path) do
          {:ok, content} -> {:ok, content}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_pages_data(storage_key) do
    case Artifacts.download_and_parse_json(storage_key) do
      {:ok, pages_jsonl} ->
        pages = pages_jsonl
        |> String.split("\n")
        |> Enum.filter(&(&1 != ""))
        |> Enum.map(&Jason.decode!/1)
        
        {:ok, pages}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_extraction_metrics(storage_key) do
    case Artifacts.download_and_parse_json(storage_key) do
      {:ok, metrics} -> {:ok, metrics}
      {:error, reason} -> {:error, reason}
    end
  end

  # Database update functions

  defp update_run_status(run_id, status) do
    from(sr in "segmentation_runs", where: sr.segmentation_run_id == ^run_id)
    |> Repo.update_all(set: [status: status, updated_at: DateTime.utc_now()])
  end

  defp update_run_completion(run_id, seg_result) do
    update_data = [
      status: "completed",
      accepted_count: seg_result.metrics.accepted_count,
      suppressed_count: seg_result.metrics.suppressed_count,
      mean_conf_boundary: seg_result.metrics.mean_conf_boundary,
      updated_at: DateTime.utc_now()
    ]
    
    from(sr in "segmentation_runs", where: sr.segmentation_run_id == ^run_id)
    |> Repo.update_all(set: update_data)
  end

  defp insert_clauses(run_id, staging_upload_id, clauses) do
    clause_data = clauses
    |> Enum.with_index(1)
    |> Enum.map(fn {clause, ordinal} ->
      %{
        segmentation_run_id: run_id,
        staging_upload_id: staging_upload_id,
        ordinal: ordinal,
        number_label: clause.number_label,
        number_label_normalized: normalize_number_label(clause.number_label),
        heading_text: clause.heading_text,
        start_char: clause.start_char,
        end_char: clause.end_char,
        start_page: clause.start_page,
        end_page: clause.end_page,
        detected_style: clause.detected_style,
        confidence_boundary: clause.confidence_boundary,
        confidence_heading: clause.confidence_heading,
        anomaly_flags: clause.anomaly_flags,
        text_snippet: clause.text_snippet
      }
    end)
    
    Repo.insert_all("clauses", clause_data, on_conflict: :nothing)
  end

  defp store_segmentation_events(run_id, events) do
    event_data = Enum.map(events, fn event ->
      %{
        segmentation_run_id: run_id,
        event_type: event.event,
        event_detail: event.detail,
        created_at: event.timestamp
      }
    end)
    
    Repo.insert_all("segmentation_events", event_data)
  end

  defp store_preview_artifact(storage_key, preview_data) do
    json_content = Jason.encode!(preview_data)
    temp_file = Path.join(System.tmp_dir!(), "preview_#{System.unique_integer()}.json")
    File.write!(temp_file, json_content)
    
    Artifacts.upload_artifact(storage_key, temp_file)
  end

  defp store_clauses_artifact(storage_key, clauses) do
    jsonl_content = clauses
    |> Enum.map(&Jason.encode!/1)
    |> Enum.join("\n")
    
    temp_file = Path.join(System.tmp_dir!(), "clauses_#{System.unique_integer()}.jsonl")
    File.write!(temp_file, jsonl_content)
    
    Artifacts.upload_artifact(storage_key, temp_file)
  end

  # Helper functions

  defp parse_segmentation_version(version) do
    case Regex.run(~r/seg-v(\d+)\.(\d+)\.(\d+)/, version) do
      [_, major, minor, patch] ->
        {String.to_integer(major), String.to_integer(minor), String.to_integer(patch)}
      _ ->
        {1, 0, 0}  # Default version
    end
  end

  defp normalize_number_label(nil), do: nil
  defp normalize_number_label(label) do
    Evhlegalchat.Segmentation.Normalize.normalize_number_label(label)
  end
end