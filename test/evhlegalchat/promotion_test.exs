defmodule Evhlegalchat.PromotionTest do
  use Evhlegalchat.DataCase, async: false # Set to false for Oban testing

  alias Evhlegalchat.Promotion
  alias Evhlegalchat.Promotion.PromoteWorker
  alias Evhlegalchat.Ingest.{StagingUpload, StagingService}
  alias Evhlegalchat.Segmentation.{SegmentationRun, Clause}
  alias Evhlegalchat.Agreement
  alias Evhlegalchat.Repo
  alias Evhlegalchat.Storage.Local
  alias Oban.Testing

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  setup do
    # Configure test environment
    temp_storage_root = Path.join(System.tmp_dir!(), "test_promotion_#{System.unique_integer()}")
    File.mkdir_p!(temp_storage_root)
    Application.put_env(:evhlegalchat, Local, root: temp_storage_root)
    
    on_exit(fn -> File.rm_rf!(temp_storage_root) end)
    
    {:ok, temp_storage_root: temp_storage_root}
  end

  describe "ready_for_promotion?/1" do
    test "returns segmentation run when ready" do
      upload = insert(:staging_upload, status: :extracted)
      run = insert(:segmentation_run, 
        staging_upload_id: upload.staging_upload_id,
        status: :completed
      )
      
      assert {:ok, ^run} = Promotion.ready_for_promotion?(upload.staging_upload_id)
    end

    test "returns error when no completed run" do
      upload = insert(:staging_upload, status: :extracted)
      
      assert {:error, :no_completed_run} = Promotion.ready_for_promotion?(upload.staging_upload_id)
    end
  end

  describe "analyze_document/2" do
    test "analyzes NDA document correctly" do
      upload = %{original_filename: "nda.pdf"}
      clauses = [
        %{heading_text: "1. Confidential Information", text_snippet: "The parties agree to maintain confidentiality"},
        %{heading_text: "2. Non-Disclosure", text_snippet: "This agreement contains trade secrets"}
      ]
      
      {doc_type, title, needs_review} = Promotion.analyze_document(upload, clauses)
      
      assert doc_type == :NDA
      assert title == "Confidential Information"
      assert needs_review == false
    end

    test "analyzes SOW document correctly" do
      upload = %{original_filename: "sow.pdf"}
      clauses = [
        %{heading_text: "1. Scope of Work", text_snippet: "The contractor will deliver specific deliverables"},
        %{heading_text: "2. Milestones", text_snippet: "Project timeline includes key milestones"}
      ]
      
      {doc_type, title, needs_review} = Promotion.analyze_document(upload, clauses)
      
      assert doc_type == :SOW
      assert title == "Scope of Work"
      assert needs_review == false
    end

    test "flags ambiguous documents for review" do
      upload = %{original_filename: "contract.pdf"}
      clauses = [
        %{heading_text: "1. General Terms", text_snippet: "This document contains general terms"},
        %{heading_text: "2. Miscellaneous", text_snippet: "Other provisions apply"}
      ]
      
      {doc_type, title, needs_review} = Promotion.analyze_document(upload, clauses)
      
      assert doc_type == :NDA # Default
      assert title == "General Terms"
      assert needs_review == true
    end
  end

  describe "compute_review_status/1" do
    test "sets unreviewed for high quality segmentation" do
      run = %{accepted_count: 5, mean_conf_boundary: 0.85}
      
      assert :unreviewed = Promotion.compute_review_status(run)
    end

    test "sets needs_review for low quality segmentation" do
      run = %{accepted_count: 2, mean_conf_boundary: 0.65}
      
      assert :needs_review = Promotion.compute_review_status(run)
    end
  end

  describe "PromoteWorker.perform/1" do
    test "successfully promotes staging upload to agreement", %{temp_storage_root: temp_storage_root} do
      # Setup staging upload and artifacts
      staging_upload_id = 1
      text_concat_key = "staging/#{staging_upload_id}/text/concatenated.txt"
      pages_jsonl_key = "staging/#{staging_upload_id}/text/pages.jsonl"
      metrics_key = "staging/#{staging_upload_id}/metrics.json"
      
      # Create staging files
      File.mkdir_p!(Path.join(temp_storage_root, "staging/#{staging_upload_id}/text"))
      File.write!(Path.join(temp_storage_root, text_concat_key), "1. Confidential Information\nThis is confidential data.\n\n2. Non-Disclosure\nParties agree to maintain confidentiality.")
      File.write!(Path.join(temp_storage_root, pages_jsonl_key), ~s([{"page": 1, "char_count": 150}]))
      File.write!(Path.join(temp_storage_root, metrics_key), ~s({"page_count": 1, "char_count": 150, "ocr": false}))
      
      upload = insert(:staging_upload,
        staging_upload_id: staging_upload_id,
        status: :extracted,
        source_hash: "abc123def456",
        original_filename: "nda.pdf",
        storage_key: "staging/#{staging_upload_id}/original/nda.pdf",
        metadata: %{"artifact_keys" => %{
          "text_concat" => text_concat_key,
          "pages_jsonl" => pages_jsonl_key,
          "metrics" => metrics_key
        }}
      )
      
      # Create original file
      File.mkdir_p!(Path.join(temp_storage_root, "staging/#{staging_upload_id}/original"))
      File.write!(Path.join(temp_storage_root, upload.storage_key), "Original PDF content")
      
      # Create completed segmentation run
      run = insert(:segmentation_run,
        staging_upload_id: staging_upload_id,
        status: :completed,
        accepted_count: 2,
        mean_conf_boundary: 0.85,
        segmentation_version: "seg-v1.0"
      )
      
      # Create sample clauses
      insert(:clause,
        segmentation_run_id: run.id,
        staging_upload_id: staging_upload_id,
        ordinal: 1,
        heading_text: "Confidential Information",
        text_snippet: "This is confidential data.",
        start_char: 0,
        end_char: 50,
        start_page: 1,
        end_page: 1,
        detected_style: "numbered_heading",
        confidence_boundary: 0.9
      )
      
      insert(:clause,
        segmentation_run_id: run.id,
        staging_upload_id: staging_upload_id,
        ordinal: 2,
        heading_text: "Non-Disclosure",
        text_snippet: "Parties agree to maintain confidentiality.",
        start_char: 51,
        end_char: 100,
        start_page: 1,
        end_page: 1,
        detected_style: "numbered_heading",
        confidence_boundary: 0.8
      )
      
      job_args = %{"staging_upload_id" => staging_upload_id}
      
      assert {:ok, :promoted} = Testing.perform_job(PromoteWorker, job_args)
      
      # Verify agreement was created
      agreement = Repo.get_by!(Agreement, source_hash: upload.source_hash)
      assert agreement.doc_type == :NDA
      assert agreement.agreement_title == "Confidential Information"
      assert agreement.status == :draft
      assert agreement.review_status == :unreviewed
      assert agreement.source_file_name == "nda.pdf"
      assert agreement.storage_key =~ "agreements/#{agreement.agreement_id}/original/"
      
      # Verify clauses were re-parented
      clauses = Repo.all(from c in Clause, where: c.segmentation_run_id == ^run.id)
      assert length(clauses) == 2
      assert Enum.all?(clauses, fn clause ->
        clause.agreement_id == agreement.agreement_id and clause.staging_upload_id == nil
      end)
      
      # Verify artifacts were promoted
      assert File.exists?(Path.join(temp_storage_root, agreement.storage_key))
      assert File.exists?(Path.join(temp_storage_root, "agreements/#{agreement.agreement_id}/text/concatenated.txt"))
      assert File.exists?(Path.join(temp_storage_root, "agreements/#{agreement.agreement_id}/text/pages.jsonl"))
      assert File.exists?(Path.join(temp_storage_root, "agreements/#{agreement.agreement_id}/metrics.json"))
    end

    test "reuses existing agreement for duplicate source hash" do
      # Create existing agreement
      existing_agreement = insert(:agreement,
        source_hash: "abc123def456",
        doc_type: :NDA,
        agreement_title: "Existing NDA"
      )
      
      # Create staging upload with same hash
      upload = insert(:staging_upload,
        staging_upload_id: 2,
        status: :extracted,
        source_hash: "abc123def456",
        original_filename: "duplicate.pdf"
      )
      
      # Create completed segmentation run
      run = insert(:segmentation_run,
        staging_upload_id: upload.staging_upload_id,
        status: :completed,
        accepted_count: 1,
        mean_conf_boundary: 0.8
      )
      
      # Create sample clause
      insert(:clause,
        segmentation_run_id: run.id,
        staging_upload_id: upload.staging_upload_id,
        ordinal: 1,
        heading_text: "New Clause",
        text_snippet: "New content",
        start_char: 0,
        end_char: 20,
        start_page: 1,
        end_page: 1,
        detected_style: "numbered_heading",
        confidence_boundary: 0.8
      )
      
      job_args = %{"staging_upload_id" => upload.staging_upload_id}
      
      assert {:ok, :reused_existing} = Testing.perform_job(PromoteWorker, job_args)
      
      # Verify no new agreement was created
      agreements = Repo.all(Agreement)
      assert length(agreements) == 1
      
      # Verify clause was re-parented to existing agreement
      clause = Repo.get_by!(Clause, segmentation_run_id: run.id)
      assert clause.agreement_id == existing_agreement.agreement_id
      assert clause.staging_upload_id == nil
    end

    test "discards when no completed segmentation run" do
      upload = insert(:staging_upload,
        staging_upload_id: 3,
        status: :extracted,
        source_hash: "xyz789"
      )
      
      job_args = %{"staging_upload_id" => upload.staging_upload_id}
      
      assert {:discard, :no_completed_run} = Testing.perform_job(PromoteWorker, job_args)
    end

    test "discards when artifacts are missing" do
      upload = insert(:staging_upload,
        staging_upload_id: 4,
        status: :extracted,
        source_hash: "missing123",
        metadata: %{"artifact_keys" => %{}}
      )
      
      run = insert(:segmentation_run,
        staging_upload_id: upload.staging_upload_id,
        status: :completed
      )
      
      job_args = %{"staging_upload_id" => upload.staging_upload_id}
      
      assert {:discard, {:missing_artifacts, _missing_keys}} = Testing.perform_job(PromoteWorker, job_args)
    end
  end
end
