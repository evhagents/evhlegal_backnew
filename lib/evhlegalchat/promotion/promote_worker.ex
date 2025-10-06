defmodule Evhlegalchat.Promotion.PromoteWorker do
  @moduledoc """
  Oban worker for promoting staged documents to canonical agreements.
  
  Handles the complete promotion pipeline including file movement,
  agreement creation, and clause re-parenting in a single transaction.
  """

  use Oban.Worker, 
    queue: :ingest,
    max_attempts: 10,
    unique: [fields: [:args], keys: [:staging_upload_id], period: 3600, states: [:available, :scheduled, :executing, :retryable]]

  require Logger
  import Ecto.Query
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Promotion.{DocType, Title, Storage}
  alias Evhlegalchat.Ingest.{StagingUpload, Artifacts}
  alias Evhlegalchat.Segmentation.{SegmentationRun, Clause}
  alias Evhlegalchat.Enrich.EnrichWorker

  @doc """
  Promotes a staging upload to a canonical agreement.
  """
  def perform(%Oban.Job{args: %{"staging_upload_id" => staging_upload_id}, attempt: attempt}) do
    Logger.metadata(staging_upload_id: staging_upload_id, attempt: attempt)

    :telemetry.span(
      [:promotion, :start],
      %{staging_upload_id: staging_upload_id, attempt: attempt},
      fn ->
        result =
          with {:ok, staging_upload} <- get_staging_upload(staging_upload_id),
               {:ok, segmentation_run} <- get_completed_segmentation_run(staging_upload_id),
               {:ok, artifacts} <- verify_artifacts(staging_upload),
               {:ok, _lock} <- acquire_advisory_lock(staging_upload_id),
               {:ok, existing_agreement} <- check_existing_agreement(staging_upload.source_hash) do
            if existing_agreement do
              handle_existing_agreement(existing_agreement, segmentation_run)
            else
              promote_new_agreement(staging_upload, segmentation_run, artifacts)
            end
          else
            {:error, {:discard, reason}} ->
              Logger.error("Promotion discarded for #{staging_upload_id}: #{inspect(reason)}")
              {:discard, reason}
            {:error, reason} ->
              Logger.error("Promotion failed for #{staging_upload_id}: #{inspect(reason)}")
              :telemetry.execute([:promotion, :error], %{reason: reason, staging_upload_id: staging_upload_id})
              {:error, reason}
          end

        # Return value for telemetry span
        {result, %{
          staging_upload_id: staging_upload_id,
          status: (case result do {:ok, s} -> s; {:discard, s} -> s; {:error, s} -> s end)
        }}
      end
    )
  end

  # Private functions

  defp get_staging_upload(staging_upload_id) do
    case Repo.get(StagingUpload, staging_upload_id) do
      nil -> {:error, {:discard, :not_found}}
      staging_upload -> {:ok, staging_upload}
    end
  end

  defp get_completed_segmentation_run(staging_upload_id) do
    query = from r in SegmentationRun,
      where: r.staging_upload_id == ^staging_upload_id,
      where: r.status == :completed,
      order_by: [desc: r.inserted_at],
      limit: 1

    case Repo.one(query) do
      nil -> {:error, {:discard, :no_completed_run}}
      run -> {:ok, run}
    end
  end

  defp verify_artifacts(staging_upload) do
    artifact_keys = Map.get(staging_upload.metadata, "artifact_keys", %{})
    
    required_keys = ["text_concat", "pages_jsonl", "metrics"]
    missing_keys = Enum.filter(required_keys, fn key ->
      not Map.has_key?(artifact_keys, key)
    end)
    
    if missing_keys != [] do
      {:error, {:discard, {:missing_artifacts, missing_keys}}}
    else
      {:ok, artifact_keys}
    end
  end

  defp acquire_advisory_lock(staging_upload_id) do
    Repo.transaction(fn ->
      Ecto.AdvisoryLock.lock("promotion_#{staging_upload_id}")
    end)
  end

  defp check_existing_agreement(source_hash) do
    query = from a in Evhlegalchat.Agreement,
      where: a.source_hash == ^source_hash,
      limit: 1

    case Repo.one(query) do
      nil -> {:ok, nil}
      agreement -> {:ok, agreement}
    end
  end

  defp handle_existing_agreement(existing_agreement, segmentation_run) do
      Logger.info("Found existing agreement for source_hash", 
        agreement_id: existing_agreement.id,
        segmentation_run_id: segmentation_run.id
      )

    # Re-parent clauses to existing agreement
    Repo.transaction(fn ->
      from(c in Clause, where: c.segmentation_run_id == ^segmentation_run.id)
      |> Repo.update_all(set: [agreement_id: existing_agreement.id, staging_upload_id: nil])
    end)

    # Update segmentation run notes
    Repo.update_all(
      from(r in SegmentationRun, where: r.id == ^segmentation_run.id),
      set: [notes: "Promoted to existing agreement #{existing_agreement.id}"]
    )

    :telemetry.execute([:promotion, :completed], %{
      agreement_id: existing_agreement.id,
      run_id: segmentation_run.id,
      reused: true
    })

    # Enqueue Step 5 enrichment for existing agreement
    Oban.insert!(EnrichWorker.new(%{"agreement_id" => existing_agreement.id}))

    {:ok, :reused_existing}
  end

  defp promote_new_agreement(staging_upload, segmentation_run, artifacts) do
    # Analyze document for type and title
    clauses = load_sample_clauses(segmentation_run.id, 3)
    {doc_type, title, needs_review} = analyze_document(staging_upload, clauses)
    
    # Compute review status
    review_status = compute_review_status(segmentation_run, needs_review)
    
    # Generate reviewer notes
    reviewer_notes = generate_reviewer_notes(staging_upload, segmentation_run, clauses)

    # Execute promotion in transaction
    Repo.transaction(fn ->
      multi = Ecto.Multi.new()
      |> Ecto.Multi.insert(:agreement, build_agreement_changeset(staging_upload, doc_type, title, review_status, reviewer_notes))
      |> Ecto.Multi.run(:promote_files, fn _repo, %{agreement: agreement} ->
        promote_artifacts(staging_upload, agreement.id, artifacts)
      end)
      |> Ecto.Multi.run(:update_storage_key, fn _repo, %{agreement: agreement, promote_files: promoted_keys} ->
        update_agreement_storage_key(agreement.id, promoted_keys.original)
      end)
      |> Ecto.Multi.run(:reparent_clauses, fn _repo, %{agreement: agreement} ->
        reparent_clauses_to_agreement(segmentation_run.id, agreement.id)
      end)
      |> Ecto.Multi.run(:mark_run_promoted, fn _repo, %{agreement: agreement} ->
        mark_segmentation_run_promoted(segmentation_run.id, agreement.id)
      end)

      case Repo.transaction(multi) do
        {:ok, %{agreement: agreement, promote_files: promoted_keys}} ->
          Logger.info("Promotion completed successfully",
            agreement_id: agreement.id,
            staging_upload_id: staging_upload.staging_upload_id,
            promoted_files: map_size(promoted_keys)
          )

          :telemetry.execute([:promotion, :completed], %{
            agreement_id: agreement.id,
            run_id: segmentation_run.id,
            moved_files: map_size(promoted_keys),
            review_status: review_status,
            reused: false
          })

          # Enqueue Step 5 enrichment for newly promoted agreement
          Oban.insert!(EnrichWorker.new(%{"agreement_id" => agreement.id}))

          {:ok, :promoted}
        {:error, step, reason, _changes} ->
          Logger.error("Promotion transaction failed",
            step: step,
            reason: reason,
            staging_upload_id: staging_upload.staging_upload_id
          )
          {:error, {:transaction_failed, step, reason}}
      end
    end)
  end

  defp analyze_document(staging_upload, clauses) do
    doc_type_result = DocType.guess(clauses)
    title_result = Title.derive(clauses, staging_upload.original_filename)
    
    doc_type = case doc_type_result do
      {:ok, type} -> type
      {:unknown, default: default} -> default
    end
    
    title = case title_result do
      {:ok, title} -> title
      {:fallback, title} -> title
    end
    
    needs_review = case {doc_type_result, title_result} do
      {{:unknown, _}, _} -> true
      {_, {:fallback, _}} -> true
      _ -> false
    end
    
    {doc_type, title, needs_review}
  end

  defp compute_review_status(segmentation_run, needs_review) do
    cond do
      needs_review -> :needs_review
      segmentation_run.accepted_count >= 3 and segmentation_run.mean_conf_boundary >= 0.7 -> :unreviewed
      true -> :needs_review
    end
  end

  defp generate_reviewer_notes(staging_upload, segmentation_run, clauses) do
    notes = []
    
    # Check document type confidence
    doc_type_result = DocType.guess(clauses)
    notes = case doc_type_result do
      {:unknown, default: default} ->
        ["Document type unclear, defaulted to #{default}" | notes]
      _ -> notes
    end
    
    # Check title derivation
    title_result = Title.derive(clauses, staging_upload.original_filename)
    notes = case title_result do
      {:fallback, _} ->
        ["Title derived from filename" | notes]
      _ -> notes
    end
    
    # Check segmentation quality
    notes = if segmentation_run.accepted_count < 3 do
      ["Low clause count (#{segmentation_run.accepted_count})" | notes]
    else
      notes
    end
    
    notes = if segmentation_run.mean_conf_boundary < 0.7 do
      ["Low confidence boundaries (#{Float.round(segmentation_run.mean_conf_boundary, 2)})" | notes]
    else
      notes
    end
    
    case notes do
      [] -> nil
      notes -> Enum.join(notes, "; ") |> String.slice(0, 500) # Truncate to reasonable length
    end
  end

  defp build_agreement_changeset(staging_upload, doc_type, title, review_status, reviewer_notes) do
    Evhlegalchat.Agreement.new_changeset(%{
      doc_type: doc_type,
      agreement_title: title,
      status: :draft,
      review_status: review_status,
      reviewer_notes: reviewer_notes,
      source_file_name: staging_upload.original_filename,
      source_hash: staging_upload.source_hash,
      ingest_timestamp: DateTime.utc_now(),
      extractor_version: "ext-v1.0",
      model_versions: %{"segmentation" => "seg-v1.0"}
    })
  end

  defp promote_artifacts(staging_upload, agreement_id, artifacts) do
    case Storage.promote!(staging_upload, agreement_id, artifacts) do
      {:ok, promoted_keys} -> {:ok, promoted_keys}
      {:error, reason} -> {:error, {:file_promotion_failed, reason}}
    end
  end

  defp update_agreement_storage_key(agreement_id, storage_key) do
    from(a in Evhlegalchat.Agreement, where: a.id == ^agreement_id)
    |> Repo.update_all(set: [storage_key: storage_key])
    |> case do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  defp reparent_clauses_to_agreement(segmentation_run_id, agreement_id) do
    from(c in Clause, where: c.segmentation_run_id == ^segmentation_run_id)
    |> Repo.update_all(set: [agreement_id: agreement_id, staging_upload_id: nil])
    |> case do
      {count, _} -> {:ok, count}
    end
  end

  defp mark_segmentation_run_promoted(segmentation_run_id, agreement_id) do
    from(r in SegmentationRun, where: r.id == ^segmentation_run_id)
    |> Repo.update_all(set: [notes: "Promoted to agreement #{agreement_id}"])
    |> case do
      {1, _} -> :ok
      {0, _} -> {:error, :not_found}
    end
  end

  defp load_sample_clauses(segmentation_run_id, limit) do
    query = from c in Clause,
      where: c.segmentation_run_id == ^segmentation_run_id,
      where: is_nil(c.deleted_at),
      order_by: c.ordinal,
      limit: ^limit

    Repo.all(query)
  end
end
