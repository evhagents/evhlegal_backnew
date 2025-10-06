defmodule Evhlegalchat.Ingest.StagingServiceTest do
  use Evhlegalchat.DataCase, async: false
  
  alias Evhlegalchat.Ingest.{StagingService, StagingUpload}
  alias Evhlegalchat.Storage.Local

  setup do
    # Create a temporary storage directory for tests
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

  describe "stage_upload/2" do
    test "successfully stages a PDF file", %{storage_root: storage_root} do
      pdf_content = <<0x25, 0x50, 0x44, 0x46, 0x20, 0x31, 0x2E, 0x33, "PDF content here">>
      temp_file = create_temp_file(pdf_content, "test.pdf")
      
      {:ok, staging_upload} = StagingService.stage_upload(temp_file.path, "test.pdf")
      
      assert staging_upload.source_hash != nil
      assert staging_upload.storage_key != nil
      assert staging_upload.content_type_detected == "application/pdf"
      assert staging_upload.original_filename == "test.pdf"
      assert staging_upload.byte_size == byte_size(pdf_content)
      assert staging_upload.status == :ready_for_extraction
      
      # Verify file was stored
      storage_file_path = Path.join(storage_root, staging_upload.storage_key)
      assert File.exists?(storage_file_path)
      
      File.rm!(temp_file.path)
    end

    test "prevents duplicate uploads based on source hash" do
      pdf_content = <<0x25, 0x50, 0x44, 0x46, 0x20, 0x31, 0x2E, 0x33, "PDF content here">>
      
      # Stage first upload
      temp_file1 = create_temp_file(pdf_content, "test1.pdf")
      {:ok, first_upload} = StagingService.stage_upload(temp_file1.path, "test1.pdf")
      
      # Stage identical content with different filename
      temp_file2 = create_temp_file(pdf_content, "test2.pdf")
      {:ok, second_upload} = StagingService.stage_upload(temp_file2.path, "test2.pdf")
      
      # Should return the same staging upload
      assert first_upload.staging_upload_id == second_upload.staging_upload_id
      assert first_upload.source_hash == second_upload.source_hash
      
      # Only one record should exist in database
      uploads = StagingService.list_staging_uploads()
      upload_count = Enum.count(uploads, &(&1.source_hash == first_upload.source_hash))
      assert upload_count == 1
      
      File.rm!(temp_file1.path)
      File.rm!(temp_file2.path)
    end

    test "rejects unsupported file types" do
      image_content = <<0xFF, 0xD8, 0xFF, 0xE0>> # JPEG header
      temp_file = create_temp_file(image_content, "test.jpg")
      
      {:error, reason} = StagingService.stage_upload(temp_file.path, "test.jpg")
      assert reason == :unsupported_type
      
      File.rm!(temp_file.path)
    end
  end

  describe "find_or_create_staging/8" do
    test "finds existing staging upload" do
      pdf_content = <<0x25, 0x50, 0x44, 0x46, 0x20, 0x31, 0x2E, 0x33>>
      temp_file = create_temp_file(pdf_content, "test.pdf")
      
      {:ok, first_upload} = StagingService.stage_upload(temp_file.path, "test.pdf")
      
      # Try to create another with same content
      {:ok, {action, upload}} = StagingService.find_or_create_staging(
        first_upload.source_hash, 
        "another.pdf", 
        "application/pdf", 
        100, 
        %{}, 
        temp_file.path, 
        :skipped
      )
      
      assert action == :existing
      assert upload.staging_upload_id == first_upload.staging_upload_id
      
      File.rm!(temp_file.path)
    end
  end

  describe "list_staging_uploads/1" do
    test "lists staging uploads ordered by insertion time" do
      # Create multiple uploads
      pdf1 = create_temp_file(<<0x25, 0x50, 0x44, 0x46, 0x31>>, "test1.pdf")
      pdf2 = create_temp_file(<<0x25, 0x50, 0x44, 0x46, 0x32>>, "test2.pdf")
      
      {:ok, _} = StagingService.stage_upload(pdf1.path, "test1.pdf")
      Process.sleep(10) # Ensure different timestamps
      {:ok, _} = StagingService.stage_upload(pdf2.path, "test2.pdf")
      
      uploads = StagingService.list_staging_uploads()
      
      assert length(uploads) >= 2
      # Newest should be first (DESC order)
      assert hd(uploads).original_filename == "test2.pdf"
      
      File.rm!(pdf1.path)
      File.rm!(pdf2.path)
    end

    test "filters by status when provided" do
      pdf_content = <<0x25, 0x50, 0x44, 0x46, 0x20, 0x31, 0x2E, 0x33>>
      temp_file = create_temp_file(pdf_content, "test.pdf")
      
      {:ok, upload} = StagingService.stage_upload(temp_file.path, "test.pdf")
      
      # Filter by status
      ready_uploads = StagingService.list_staging_uploads(status: :ready_for_extraction)
      filtered_upload = Enum.find(ready_uploads, &(&1.staging_upload_id == upload.staging_upload_id))
      
      assert filtered_upload != nil
      assert filtered_upload.status == :ready_for_extraction
      
      File.rm!(temp_file.path)
    end
  end

  # Helper functions

  defp create_temp_file(content, filename) do
    tmp_dir = System.tmp_dir!()
    random_prefix = :rand.uniform(1_000_000)
    file_path = Path.join(tmp_dir, "#{random_prefix}_#{filename}")
    
    File.write!(file_path, content)
    
    %{path: file_path, filename: filename}
  end
end
