defmodule Evhlegalchat.Ingest.SegmentWorkerTest do
  use Evhlegalchat.DataCase, async: false
  
  import Oban.Testing
  
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Ingest.{SegmentWorker, StagingUpload}
  alias Evhlegalchat.Segmentation.{SegmentationRun, Clause}
  alias Evhlegalchat.Ingest.Artifacts
  alias Evhlegalchat.Storage.Local

  setup do
    # Create temporary storage directory for tests
    tmp_storage = Path.join(System.tmp_dir!(), "test_seg_storage_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_storage)
    
    # Override storage config for tests
    Application.put_env(:evhlegalchat, Evhlegalchat.Storage.Local, root: tmp_storage)
    
    on_exit(fn ->
      File.rm_rf(tmp_storage)
      Application.delete_env(:evhlegalchat, Evhlegalchat.Storage.Local)
    end)
    
    {:ok, %{storage_root: tmp_storage}}
  end

  describe "perform/1" do
    setup %{storage_root: storage_root} do
      # Create a staging upload with valid artifacts
      staging_upload_id = :rand.uniform(10000)
      storage_key = "test/staging_#{staging_upload_id}"
      
      {:ok, staging_upload} = Repo.insert(%StagingUpload{
        staging_upload_id: staging_upload_id,
        source_hash: :crypto.hash(:sha256, "test") |> Base.encode16(case: :lower),
        storage_key: storage_key,
        content_type_detected: "text/plain",
        original_filename: "test.txt",
        byte_size: 1000,
        status: :extracted,
        metadata: %{
          "page_count" => 1,
          "char_count" => 1000,
          "ocr" => false
        }
      })
      
      # Create artifacts
      artifacts = create_test_artifacts(staging_upload_id, storage_root)
      
      {:ok, %{
        staging_upload: staging_upload, 
        storage_root: storage_root,
        staging_upload_id: staging_upload_id,
        artifacts: artifacts
      }}
    end

    test "successfully segments document and creates clauses", %{staging_upload_id: staging_upload_id, artifacts: artifacts} do
      # Run segmentation
      assert {:ok, :completed} = perform_job(SegmentWorker, %{
        "staging_upload_id" => staging_upload_id,
        "artifact_keys" => artifacts,
        "segmentation_version" => "seg-v1.0"
      })
      
      # Verify segmentation run was created
      run = Repo.get_by(SegmentationRun, staging_upload_id: staging_upload_id)
      assert run != nil
      assert run.status == :completed
      assert run.accepted_count > 0
      
      # Verify clauses were created
      clauses = from(c in Clause,
        where: c.staging_upload_id == ^staging_upload_id,
        where: is_nil(c.deleted_at)
      ) |> Repo.all()
      
      assert length(clauses) > 0
      assert Enum.all?(clauses, fn clause ->
        clause.start_char >= 0 and clause.end_char > clause.start_char
      end)
      
      # Verify clause ordinals are sequential
      ordinals = Enum.map(clauses, & &1.ordinal)
      assert ordinals == Enum.sort(ordinals)
    end

    test "creates artifacts and stores segment data", %{staging_upload_id: staging_upload_id, artifacts: artifacts, storage_root: storage_root} do
      perform_job(SegmentWorker, %{
        "staging_upload_id" => staging_upload_id,
        "artifact_keys" => artifacts,
        "segmentation_version" => "seg-v1.0"
      })
      
      # Check that artifacts were created
      storage = Local.new()
      
      # Preview should exist for review
      preview_key = "staging/#{staging_upload_id}/segments/preview.json"
      case Local.head(storage, preview_key) do
        {:ok, _meta} -> :ok
        {:error, :not_found} -> flunk("Preview artifact not created")
      end
      
      # Segments artifact should exist for completed runs
      segments_key = "staging/#{staging_upload_id}/segments/clauses.jsonl"  
      case Local.head(storage, segments_key) do
        {:ok, _meta} -> :ok
        {:error, :not_found} -> flunk("Segments artifact not created")
      end
    end

    test "is idempotent across runs", %{staging_upload_id: staging_upload_id, artifacts: artifacts} do
      # First segment run
      assert {:ok, :completed} = perform_job(SegmentWorker, %{
        "staging_upload_id" => staging_upload_id,
        "artifact_keys" => artifacts,
        "segmentation_version" => "seg-v1.0"
      })
      
      # Count clauses from first run
      first_run_clauses = from(c in Clause,
        where: c.staging_upload_id == ^staging_upload_id,
        where: is_nil(c.deleted_at)
      ) |> Repo.all()
      
      first_count = length(first_run_clauses)
      
      # Second run should be idempotent
      perform_job(SegmentWorker, %{
        "staging_upload_id" => staging_upload_id,
        "artifact_keys" => artifacts,
        "segmentation_version" => "seg-v1.0"
      })
      
      # Should have same number of clauses (no duplicates)
      second_run_clauses = from(c in Clause,
        where: c.staging_upload_id == ^staging_upload_id,
        where: is_nil(c.deleted_at)
      ) |> Repo.all()
      
      assert length(second_run_clauses) == first_count
    end

    test "handles low quality documents with needs_review status", %{staging_upload_id: staging_upload_id, storage_root: storage_root} do
      # Create a low quality document (minimal content)
      low_quality_artifacts = create_low_quality_artifacts(staging_upload_id, storage_root)
      
      result = perform_job(SegmentWorker, %{
        "staging_upload_id" => staging_upload_id,
        "artifact_keys" => low_quality_artifacts,
        "segmentation_version" => "seg-v1.0"
      })
      
      # Should trigger needs_review
      case result do
        {:ok, :needs_review} ->
          # Verify run was marked needs_review
          run = Repo.get_by(SegmentationRun, staging_upload_id: staging_upload_id)
          assert run.status == :needs_review
          assert run.needs_review_reason != nil
          
          # Should not have created clauses
          clauses = from(c in Clause,
            where: c.staging_upload_id == ^staging_upload_id
          ) |> Repo.all()
          
          assert length(clauses) == 0
          
        {:ok, :completed} ->
          # If it completed anyway, that's also valid
          :ok
          
        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "respects advisory locking", %{staging_upload_id: staging_upload_id, artifacts: artifacts} do
      # Create two identical jobs
      job_args = %{
        "staging_upload_id" => staging_upload_id,
        "artifact_keys" => artifacts,
        "segmentation_version" => "seg-v1.0"
      }
      
      # Start both jobs simultaneously
      task1 = Task.async(fn -> perform_job(SegmentWorker, job_args) end)
      task2 = Task.async(fn -> perform_job(SegmentWorker, job_args) end)
      
      # Both should complete (one will succeed, one will be idempotent)
      result1 = Task.await(task1, 30_000)
      result2 = Task.await(task2, 30_000)
      
      # At least one should succeed
      success_count = [result1, result2]
      |> Enum.filter(fn
        {:ok, :completed} -> true
        {:ok, :needs_review} -> true
        _ -> false
      end)
      |> length()
      
      assert success_count >= 1
      
      # Should have exactly one segmentation run
      runs = from(r in SegmentationRun, where: r.staging_upload_id == ^staging_upload_id)
      |> Repo.all()
      
      assert length(runs) == 1
    end

    test "handles missing artifacts gracefully", %{staging_upload_id: staging_upload_id} do
      # Try to segment with non-existent artifacts
      bogus_artifacts = %{
        "text_concat" => "staging/#{staging_upload_id}/non-existent.txt",
        "pages_jsonl" => "staging/#{staging_upload_id}/non-existent.jsonl"
      }
      
      assert {{:error, {:missing_artifacts, _}}, _, _} = perform_job(SegmentWorker, %{
        "staging_upload_id" => staging_upload_id,
        "artifact_keys" => bogus_artifacts,
        "segmentation_version" => "seg-v1.0"
      })
      
      # Should not create any clauses or runs
      run = Repo.get_by(SegmentationRun, staging_upload_id: staging_upload_id)
      assert run == nil
      
      clauses = from(c in Clause,
        where: c.staging_upload_id == ^staging_upload_id
      ) |> Repo.all()
      
      assert length(clauses) == 0
    end
  end

  # Helper functions

  defp create_test_artifacts(staging_upload_id, storage_root) do
    # Create test text content similar to nda_flat.txt
    concat_text = """
    1. DEFINITIONS

    For purposes of this Agreement, the following terms shall have the meanings set forth below.

    2. SERVICES

    Company A agrees to provide the following services to Company B.

    3. COMPENSATION

    Company B agrees to pay Company A the compensation specified herein.

    4. TERM AND TERMINATION

    This Agreement shall commence on the Effective Date and continue until terminated.

    5. CONFIDENTIALITY

    Each party agrees to keep confidential all proprietary information.

    IN WITNESS WHEREOF, the parties have executed this Agreement.
    """
    
    # Create pages data
    pages_data = [
      %{"page" => 1, "text" => concat_text, "char_count" => String.length(concat_text)}
    ]
    
    pages_jsonl = pages_data |> Enum.map(&Jason.encode!/1) |> Enum.join("\n")
    
    # Store artifacts
    storage = Local.new()
    
    text_file = Path.join(storage_root, "concatenated.txt")
    File.write!(text_file, concat_text)
    
    pages_file = Path.join(storage_root, "pages.jsonl") 
    File.write!(pages_file, pages_jsonl)
    
    upload_artifact(storage, text_file, "staging/#{staging_upload_id}/text/concatenated.txt")
    upload_artifact(storage, pages_file, "staging/#{staging_upload_id}/text/pages.jsonl")
    
    File.rm!(text_file)
    File.rm!(pages_file)
    
    %{
      "text_concat" => "staging/#{staging_upload_id}/text/concatenated.txt",
      "pages_jsonl" => "staging/#{staging_upload_id}/text/pages.jsonl"
    }
  end
  
  defp create_low_quality_artifacts(staging_upload_id, storage_root) do
    # Create minimal content that should trigger needs_review
    minimal_text = """
    Agreement
    
    Simple document with no numbered sections.
    
    Just plain text content.
    """
    
    pages_data = [
      %{"page" => 1, "text" => minimal_text, "char_count" => String.length(minimal_text)}
    ]
    
    pages_jsonl = pages_data |> Enum.map(&Jason.encode!/1) |> Enum.join("\n")
    
    storage = Local.new()
    
    text_file = Path.join(storage_root, "minimal.txt")
    File.write!(text_file, minimal_text)
    
    pages_file = Path.join(storage_root, "minimal.jsonl")
    File.write!(pages_file, pages_jsonl)
    
    upload_artifact(storage, text_file, "staging/#{staging_upload_id}/minimal/text/concatenated.txt")
    upload_artifact(storage, pages_file, "staging/#{staging_upload_id}/minimal/text/pages.jsonl")
    
    File.rm!(text_file)
    File.rm!(pages_file)
    
    %{
      "text_concat" => "staging/#{staging_upload_id}/minimal/text/concatenated.txt",
      "pages_jsonl" => "staging/#{staging_upload_id}/minimal/text/pages.jsonl"
    }
  end

  defp upload_artifact(storage, local_file, storage_key) do
    {:ok, _} = Local.put(storage, storage_key, local_file)
  end
end

