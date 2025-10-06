defmodule Evhlegalchat.Ingest.Events do
  @moduledoc """
  Event publishing for Step 2 → Step 3 coordination.
  
  Provides event-driven communication between extraction and segmentation stages.
  """

  require Logger

  @doc """
  Publishes extraction completion event for Step 3 coordination.
  
  This event signals that extraction is complete and artifacts are available.
  Step 3 components can listen for this event to trigger segmentation.
  """
  def publish_extraction_ready(staging_upload_id, artifact_keys, metadata) do
    _event = %{
      event_type: :extraction_ready,
      staging_upload_id: staging_upload_id,
      artifact_keys: artifact_keys,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    Logger.info("Publishing extraction_ready event",
      staging_upload_id: staging_upload_id,
      artifact_count: map_size(artifact_keys)
    )

    # For now, we'll use direct Oban job insertion for Step 3
    # In a full event-driven system, this would publish to a message bus
    enqueue_segmentation_job(staging_upload_id, artifact_keys, metadata)
    
    # Emit telemetry for observability
    :telemetry.execute([:evhlegalchat, :ingest, :extraction_ready], 
      %{artifact_count: map_size(artifact_keys)}, 
      %{staging_upload_id: staging_upload_id}
    )
  end

  @doc """
  Publishes extraction failure event.
  
  Signals that extraction failed and cleanup may be needed.
  """
  def publish_extraction_failure(staging_upload_id, reason, metadata) do
    _event = %{
      event_type: :extraction_failure,
      staging_upload_id: staging_upload_id,
      reason: reason,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    Logger.error("Publishing extraction_failure event",
      staging_upload_id: staging_upload_id,
      reason: reason
    )

    # Emit telemetry for observability
    :telemetry.execute([:evhlegalchat, :ingest, :extraction_failure],
      %{failure_reason: reason},
      %{staging_upload_id: staging_upload_id}
    )
  end

  @doc """
  Publishes artifact processing event.
  
  Signals that specific artifacts have been successfully stored.
  """
  def publish_artifact_stored(staging_upload_id, artifact_type, storage_key, size) do
    Logger.debug("Artifact stored",
      staging_upload_id: staging_upload_id,
      artifact_type: artifact_type,
      storage_key: storage_key,
      size: size
    )

    # Emit telemetry for artifact tracking
    :telemetry.execute([:evhlegalchat, :ingest, :artifact_stored],
      %{size_bytes: size},
      %{
        staging_upload_id: staging_upload_id,
        artifact_type: artifact_type
      }
    )
  end

  @doc """
  Publishes blocking event for problematic files.
  
  Signals that a file should be permanently blocked from extraction.
  """
  def publish_extraction_blocked(staging_upload_id, source_hash, attempt_count, reason) do
    Logger.warning("Extraction blocked for problematic file",
      staging_upload_id: staging_upload_id,
      source_hash: source_hash,
      attempt_count: attempt_count,
      reason: reason
    )

    # Add to persistent blocklist (could be in-memory cache or database)
    add_to_blocklist(source_hash, reason)

    # Emit telemetry for monitoring
    :telemetry.execute([:evhlegalchat, :ingest, :extraction_blocked],
      %{attempt_count: attempt_count},
      %{
        staging_upload_id: staging_upload_id,
        source_hash: source_hash,
        reason: reason
      }
    )
  end

  @doc """
  Checks if a source hash is in the extraction blocklist.
  
  Returns true if the hash is blocked, false otherwise.
  """
  def blocked?(source_hash) when is_binary(source_hash) do
    case :ets.lookup(:extraction_blocklist, source_hash) do
      [{^source_hash, _reason}] -> true
      [] -> false
    end
  end

  @doc """
  Subscribes to extraction events.
  
  This is a stub for future event-driven architecture.
  Currently used for documentation and telemetry.
  """
  def subscribe(event_types) when is_list(event_types) do
    # In a production event system, this would subscribe to persistent event streams
    Logger.info("Subscribing to extraction events", event_types: event_types)
    
    # For now, this is primarily for documentation
    :ok
  end

  # Private functions

  defp enqueue_segmentation_job(staging_upload_id, artifact_keys, metadata) do
    # This will be implemented when Step 3 segmentation is built
    # For now, just log the intent
    
    Logger.info("Would enqueue segmentation job (Step 3)",
      staging_upload_id: staging_upload_id,
      artifact_keys: Map.keys(artifact_keys),
      page_count: Map.get(metadata, "page_count", 0),
      char_count: Map.get(metadata, "char_count", 0)
    )

    # Placeholder for Oban job insertion
    # SegmentationJob.new(%{
    #   staging_upload_id: staging_upload_id,
    #   artifact_keys: artifact_keys,
    #   metadata: metadata
    # })
    # |> Oban.insert(queue: :segment)
  end

  defp add_to_blocklist(source_hash, reason) do
    # Add to ETS table for in-memory blocking (permanent across restarts)
    :ets.insert(:extraction_blocklist, {source_hash, reason})
    
    # Could also add to database-backed blocklist for persistence
    Logger.info("Added to extraction blocklist",
      source_hash: String.slice(source_hash, 0, 8) <> "...",
      reason: reason
    )
  end
end
