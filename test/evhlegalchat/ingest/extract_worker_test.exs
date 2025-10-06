defmodule Evhlegalchat.Ingest.ExtractWorkerTest do
  use Evhlegalchat.DataCase, async: false
  
  import Oban.Testing
  
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Ingest.{StagingUpload, ExtractWorker}
  alias Evhlegalchat.Storage.Local

  setup do
    # Create temporary storage directory for tests
    tmp_storage = Path.join(System.tmp_dir!(), "test_storage_#{:rand.uniform(1_000_000)}")
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
      # Create a staging upload ready for extraction
      storage_key = "test/sample.txt"
      local_storage_path = Path.join(storage_root, storage_key)
      
      File.mkdir_p!(Path.dirname(local_storage_path))
      File.write!(local_storage_path, "Sample text content")
      
      {:ok, staging_upload} = Repo.insert(%StagingUpload{
        source_hash: :crypto.hash(:sha256, "test content") |> Base.encode16(case: :lower),
        storage_key: storage_key,
        content_type_detected: "text/plain",
        original_filename: "sample.txt",
        byte_size: 100,
        status: :ready_for_extraction,
        metadata: %{}
      })
      
      {:ok, %{staging_upload: stag staging_upload, storage_path: local_storage_path}}
    end

    test "extracts text and updates metadata", %{staging_upload: staging_upload} do
      assert {:ok, _} = perform_job(ExtractWorker, %{"staging_upload_id" => staging_upload.staging_upload_id})
      
      # Verify staging upload was updated
      updated = Repo.get!(StagingUpload, staging_upload.staging_upload_id)
      assert updated.status == :extracted
      assert updated.metadata["page_count"] == 1
      assert updated.metadata["char_count"] > 0
      assert updated.metadata["word_count"] > 0
      assert updated.metadata["artifact_keys"]["text_concat"]
      assert updated.metadata["artifact_keys"]["metrics"]
      assert updated.metadata["ocr"] == false
    end

    test "is idempotent when artifacts exist", %{staging_upload: staging_upload} do
      # First run
      assert {:ok, _} = perform_job(ExtractWorker, %{"staging_upload_id" => staging_upload.id})
      
      # Second run should short-circuit
      perform_job(ExtractWorker, %{"staging_upload_id" => staging_upload.id})
      
      updated = Repo.get!(StagingUpload, staging_upload.id)
      assert updated.status == :extracted
    end

    test "rejects unsupported MIME type", %{storage_root: storage_root} do
      # Create staging upload with unsupported MIME
      {:ok, staging_upload} = Repo.insert(%StagingUpload{
        source_hash: :crypto.hash(:sha256, "test") |> Base.encode16(case: :lower),
        storage_key: "test/unknown.xyz",
        content_type_detected: "application/x-unknown",
        original_filename: "unknown.xyz",
        byte_size: 100,
        status: :ready_for_extraction,
        metadata: %{}
      })
      
      # Create dummy file
      storage_path = Path.join(storage_root, "test/unknown.xyz")
      File.mkdir_p!(Path.dirname(storage_path))
      File.write!(storage_path, "dummy content")
      
      assert :discard = perform_job(ExtractWorker, %{"staging_upload_id" => staging_upload.id})
      
      updated = Repo.get!(StagingUpload, staging_upload.id)
      assert updated.status == :rejected
      assert updated.rejection_reason =~ "unsupported_mime"
    end

    test "handles file not found in storage", %{storage_root: storage_root} do
      {:ok, staging_upload} = Repo.insert(%StagingUpload{
        source_hash: :crypto.hash(:sha256, "test_not_found") |> Base.encode16(case: :lower),
        storage_key: "test/nonexistent.txt",
        content_type_detected: "text/plain",
        original_filename: "nonexistent.txt",
        byte_size: 100,
        status: :ready_for_extraction,
        metadata: %{}
      })
      
      # Don't create the file, so it won't be found
      
      assert {:error, _} = perform_job(ExtractWorker, %{"staging_upload_id" => staging_upload.id})
      
      updated = Repo.get!(StagingUpload, staging_upload.id)
      assert updated.status == :error
    end

    test "blocks retryable staging uploads after poison pill threshold", %{storage_root: storage_root} do
      {:ok, staging_upload} = Repo.insert(%StagingUpload{
        source_hash: :crypto.hash(:sha256, "poison_pill_test") |> Base.encode16(case: :lower),
        storage_key: "test/poison.txt",
        content_type_detected: "text/plain",
        original_filename: "poison.txt",
        byte_size: 100,
        status: :ready_for_extraction,
        metadata: %{}
      })
      
      # Create a file that will cause consistent failures
      storage_path = Path.join(storage_root, "test/poison.txt")
      File.mkdir_p!(Path.dirname(storage_path))
      File.write!(storage_path, "dummy content")
      
      # Simulate multiple failures by directly updating the staging upload to error status
      # (In real scenarios, this would happen through multiple worker executions)
      Enum.each(1..4, fn _attempt ->
        staging_upload
        |> StagingUpload.changeset(%{status: :error})
        |> Repo.update()
      end)
      
      # Now run extraction - should be blocked
      assert :discard = perform_job(ExtractWorker, %{"staging_upload_id" => staging_upload.id})
      
      updated = Repo.get!(StagingUpload, staging_upload.id)
      assert updated.status == :rejected
      assert updated.rejection_reason == "extraction_unstable"
    end

    test "validates status before processing" do
      {:ok, staging_upload} = Repo.insert(%StagingUpload{
        source_hash: :crypto.hash(:sha256, "already_extracted") |> Base.encode16(case: :lower),
        storage_key: "test/already.txt",
        content_type_detected: "text/plain",
        original_filename: "already.txt",
        byte_size: 100,
        status: :extracted,  # Already extracted
        metadata: %{}
      })
      
      assert {:error, _} = perform_job(ExtractWorker, %{"staging_upload_id" => staging_upload.id})
      
      # Status should remain unchanged
      updated = Repo.get!(StagingUpload, staging_upload.id)
      assert updated.status == :extracted
    end
  end

  describe "idempotency" do
    test "short-circuits when artifacts exist and are valid", %{storage_root: storage_root} do
      staging_upload_id = :rand.uniform(10000)
      
      # Create staging upload with pre-existing artifacts
      {:ok, staging_upload} = Repo.insert(%StagingUpload{
        staging_upload_id: staging_upload_id,
        source_hash: :crypto.hash(:sha256, "idempotent_test") |> Base.encode16(case: :lower),
        storage_key: "test/idempotent.txt",
        content_type_detected: "text/plain",
        original_filename: "idempotent.txt",
        byte_size: 100,
        status: :ready_for_extraction,
        metadata: %{
          "artifact_keys" => %{
            "text_concat" => "staging/#{staging_upload_id}/text/concatenated.txt",
            "metrics" => "staging/#{staging_upload_id}/metrics.json"
          }
        }
      })
      
      # Create storage and artifacts
      storage = Local.new()
      text_content = "Pre-existing text content"
      metrics_json = Jason.encode!(%{"page_count" => 1, "char_count" => 25})
      
      # Create text artifact
      text_file = Path.join(storage_root, "staging/#{staging_upload_id}/text/concatenated.txt")
      File.mkdir_p!(Path.dirname(text_file))
      File.write!(text_file, text_content)
      
      # Create metrics artifact  
      metrics_file = Path.join(storage_root, "staging/#{staging_upload_id}/metrics.json")
      File.mkdir_p!(Path.dirname(metrics_file))
      File.write!(metrics_file, metrics_json)
      
      # Run extraction
      result = perform_job(ExtractWorker, %{"staging_upload_id" => staging_upload_id})
      
      # Should short-circuit since artifacts exist
      assert {:ok, {:already_extracted}} = result
      
      # Storage entry should remain as-is (no duplicate artifacts created)
      assert File.exists?(text_file)
      assert File.exists?(metrics_file)
    end
  end
end
