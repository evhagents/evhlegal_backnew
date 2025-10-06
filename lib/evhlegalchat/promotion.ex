defmodule Evhlegalchat.Promotion do
  @moduledoc """
  Orchestration helpers for promoting staged documents to canonical agreements.
  
  This module provides high-level functions for the promotion pipeline,
  coordinating between segmentation results, file promotion, and agreement creation.
  """

  require Logger
  alias Evhlegalchat.Promotion.{DocType, Title, Storage}
  alias Evhlegalchat.Ingest.{StagingUpload, Artifacts}
  alias Evhlegalchat.Segmentation.SegmentationRun
  alias Evhlegalchat.Repo
  import Ecto.Query

  @doc """
  Determines if a staging upload is ready for promotion.
  
  Returns {:ok, segmentation_run} if ready, {:error, reason} if not.
  """
  def ready_for_promotion?(staging_upload_id) do
    query = from r in SegmentationRun,
      where: r.staging_upload_id == ^staging_upload_id,
      where: r.status == :completed,
      order_by: [desc: r.inserted_at],
      limit: 1

    case Repo.one(query) do
      nil -> {:error, :no_completed_run}
      run -> {:ok, run}
    end
  end

  @doc """
  Loads staging upload with required artifacts for promotion.
  
  Returns {:ok, staging_upload, artifacts} or {:error, reason}.
  """
  def load_promotion_data(staging_upload_id) do
    with {:ok, staging_upload} <- get_staging_upload(staging_upload_id),
         {:ok, artifacts} <- verify_artifacts(staging_upload) do
      {:ok, staging_upload, artifacts}
    end
  end

  @doc """
  Determines document type and title from segmentation results.
  
  Returns {doc_type, title, confidence} where confidence indicates
  if manual review is needed.
  """
  def analyze_document(staging_upload, segmentation_run) do
    # Load first few clauses for analysis
    clauses = load_sample_clauses(segmentation_run.id, 3)
    
    # Determine document type
    doc_type_result = DocType.guess(clauses)
    
    # Derive title
    title_result = Title.derive(clauses, staging_upload.source_file_name)
    
    # Combine results
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

  @doc """
  Computes confidence gates for review status.
  
  Returns review_status based on segmentation quality metrics.
  """
  def compute_review_status(segmentation_run) do
    cond do
      segmentation_run.accepted_count >= 3 and segmentation_run.mean_conf_boundary >= 0.7 ->
        :unreviewed
      true ->
        :needs_review
    end
  end

  @doc """
  Generates reviewer notes based on promotion analysis.
  
  Returns a string with warnings and recommendations.
  """
  def generate_reviewer_notes(doc_type_result, title_result, segmentation_run) do
    notes = []
    
    notes = case doc_type_result do
      {:unknown, default: default} ->
        ["Document type unclear, defaulted to #{default}" | notes]
      _ -> notes
    end
    
    notes = case title_result do
      {:fallback, _} ->
        ["Title derived from filename" | notes]
      _ -> notes
    end
    
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
      notes -> Enum.join(notes, "; ")
    end
  end

  # Private functions

  defp get_staging_upload(staging_upload_id) do
    case Repo.get(StagingUpload, staging_upload_id) do
      nil -> {:error, :not_found}
      staging_upload -> {:ok, staging_upload}
    end
  end

  defp verify_artifacts(staging_upload) do
    artifact_keys = Map.get(staging_upload.metadata, "artifact_keys", %{})
    
    required_keys = ["text_concat", "pages_jsonl", "metrics"]
    
    missing_keys = Enum.filter(required_keys, fn key ->
      not Map.has_key?(artifact_keys, key)
    end)
    
    if missing_keys != [] do
      {:error, {:missing_artifacts, missing_keys}}
    else
      {:ok, artifact_keys}
    end
  end

  defp load_sample_clauses(segmentation_run_id, limit) do
    query = from c in Evhlegalchat.Segmentation.Clause,
      where: c.segmentation_run_id == ^segmentation_run_id,
      where: is_nil(c.deleted_at),
      order_by: c.ordinal,
      limit: ^limit

    Repo.all(query)
  end
end
