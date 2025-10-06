defmodule Evhlegalchat.Ingest.FileIdTest do
  use ExUnit.Case, async: true
  
  alias Evhlegalchat.Ingest.FileId

  describe "sha256_file/1" do
    test "computes SHA256 hash of a file" do
      temp_file = create_temp_file("test content", "test.txt")
      
      {:ok, hash} = FileId.sha256_file(temp_file.path)
      
      assert is_binary(hash)
      assert String.length(hash) == 64
      assert String.match?(hash, ~r/^[a-f0-9]+$/)
      
      File.rm!(temp_file.path)
    end

    test "handles non-existent file" do
      {:error, _reason} = FileId.sha256_file("nonexistent.txt")
    end
  end

  describe "detect_mime/1" do
    test "detects PDF from magic bytes" do
      pdf_content = <<0x25, 0x50, 0x44, 0x46, 0x20, 0x31, 0x2E, 0x33>> # PDF header
      temp_file = create_temp_file(pdf_content, "test.pdf")
      
      {:ok, mime_type} = FileId.detect_mime(temp_file.path)
      
      assert mime_type == "application/pdf"
      
      File.rm!(temp_file.path)
    end

    test "detects DOCX from magic bytes" do
      docx_content = <<0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00>> # ZIP header (DOCX)
      temp_file = create_temp_file(docx_content, "test.docx")
      
      {:ok, mime_type} = FileId.detect_mime(temp_file.path)
      
      assert mime_type == "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      
      File.rm!(temp_file.path)
    end

    test "detects plain text" do
      text_content = "This is plain text content."
      temp_file = create_temp_file(text_content, "test.txt")
      
      {:ok, mime_type} = FileId.detect_mime(temp_file.path)
      
      assert mime_type == "text/plain"
      
      File.rm!(temp_file.path)
    end

    test "handles file too small" do
      tiny_content = "hi"
      temp_file = create_temp_file(tiny_content, "test.txt")
      
      {:error, :insufficient_data} = FileId.detect_mime(temp_file.path)
      
      File.rm!(temp_file.path)
    end
  end

  describe "supported_extension?/1" do
    test "recognizes supported extensions" do
      assert FileId.supported_extension?("document.pdf") == true
      assert FileId.supported_extension?("document.docx") == true
      assert FileId.supported_extension?("document.txt") == true
    end

    test "rejects unsupported extensions" do
      assert FileId.supported_extension?("document.doc") == false
      assert FileId.supported_extension?("document.jpg") == false
      assert FileId.supported_extension?("document") == false
    end
  end

  describe "identify_file/2" do
    test "successfully identifies a PDF file" do
      pdf_content = <<0x25, 0x50, 0x44, 0x46, 0x20, 0x31, 0x2E, 0x33>>
      temp_file = create_temp_file(pdf_content, "test.pdf")
      
      {:ok, hash, mime_type} = FileId.identify_file(temp_file.path)
      
      assert is_binary(hash)
      assert mime_type == "application/pdf"
      
      File.rm!(temp_file.path)
    end

    test "rejects unsupported file types" do
      image_content = <<0xFF, 0xD8, 0xFF, 0xE0>> # JPEG header
      temp_file = create_temp_file(image_content, "test.jpg")
      
      {:error, :unsupported_type} = FileId.identify_file(temp_file.path)
      
      File.rm!(temp_file.path)
    end
  end

  # Helper functions

  defp create_temp_file(content, extension) do
    tmp_dir = System.tmp_dir!()
    filename = "test_#{:rand.uniform(1_000_000)}#{extension}"
    file_path = Path.join(tmp_dir, filename)
    
    File.write!(file_path, content)
    
    %{path: file_path, filename: filename}
  end
end