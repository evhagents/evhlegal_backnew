defmodule Evhlegalchat.Promotion.StorageTest do
  use ExUnit.Case, async: false # Set to false for file system operations

  alias Evhlegalchat.Promotion.Storage
  alias Evhlegalchat.Storage.Local

  setup do
    # Create a temporary directory for test storage
    temp_storage_root = Path.join(System.tmp_dir!(), "test_promotion_storage_#{System.unique_integer()}")
    File.mkdir_p!(temp_storage_root)
    
    # Configure Local storage for tests
    Application.put_env(:evhlegalchat, Local, root: temp_storage_root)
    
    on_exit(fn -> File.rm_rf!(temp_storage_root) end)
    
    {:ok, temp_storage_root: temp_storage_root}
  end

  test "builds canonical keys correctly" do
    keys = Storage.build_canonical_keys(123)
    
    assert keys.original == "agreements/123/original/"
    assert keys.text == "agreements/123/text/"
    assert keys.metrics == "agreements/123/metrics.json"
    assert keys.previews == "agreements/123/previews/"
  end

  test "promotes artifacts successfully", %{temp_storage_root: temp_storage_root} do
    # Setup staging artifacts
    staging_upload_id = 1
    agreement_id = 100
    
    staging_text_key = "staging/#{staging_upload_id}/text/concatenated.txt"
    staging_pages_key = "staging/#{staging_upload_id}/text/pages.jsonl"
    staging_metrics_key = "staging/#{staging_upload_id}/metrics.json"
    
    # Create staging files
    File.mkdir_p!(Path.join(temp_storage_root, "staging/#{staging_upload_id}/text"))
    File.write!(Path.join(temp_storage_root, staging_text_key), "Sample document text")
    File.write!(Path.join(temp_storage_root, staging_pages_key), ~s([{"page": 1, "char_count": 100}]))
    File.write!(Path.join(temp_storage_root, staging_metrics_key), ~s({"page_count": 1, "char_count": 100}))
    
    # Create staging upload mock
    staging_upload = %{
      staging_upload_id: staging_upload_id,
      source_hash: "abc123def456",
      original_filename: "test.pdf",
      storage_key: "staging/#{staging_upload_id}/original/test.pdf"
    }
    
    # Create original file
    File.mkdir_p!(Path.join(temp_storage_root, "staging/#{staging_upload_id}/original"))
    File.write!(Path.join(temp_storage_root, staging_upload.storage_key), "Original PDF content")
    
    artifacts = %{
      "text_concat" => staging_text_key,
      "pages_jsonl" => staging_pages_key,
      "metrics" => staging_metrics_key
    }
    
    # Promote artifacts
    assert {:ok, promoted_keys} = Storage.promote!(staging_upload, agreement_id, artifacts)
    
    # Verify promoted files exist
    assert File.exists?(Path.join(temp_storage_root, promoted_keys.original))
    assert File.exists?(Path.join(temp_storage_root, promoted_keys.text_concat))
    assert File.exists?(Path.join(temp_storage_root, promoted_keys.pages_jsonl))
    assert File.exists?(Path.join(temp_storage_root, promoted_keys.metrics))
    
    # Verify content integrity
    assert File.read!(Path.join(temp_storage_root, promoted_keys.text_concat)) == "Sample document text"
    assert File.read!(Path.join(temp_storage_root, promoted_keys.pages_jsonl)) == ~s([{"page": 1, "char_count": 100}])
    assert File.read!(Path.join(temp_storage_root, promoted_keys.metrics)) == ~s({"page_count": 1, "char_count": 100})
  end

  test "handles missing artifacts gracefully" do
    staging_upload = %{
      staging_upload_id: 1,
      source_hash: "abc123",
      original_filename: "test.pdf",
      storage_key: "staging/1/original/test.pdf"
    }
    
    artifacts = %{
      "text_concat" => "missing/file.txt",
      "pages_jsonl" => "missing/pages.jsonl",
      "metrics" => "missing/metrics.json"
    }
    
    assert {:error, _reason} = Storage.promote!(staging_upload, 100, artifacts)
  end

  test "promotes preview files when available", %{temp_storage_root: temp_storage_root} do
    staging_upload_id = 1
    agreement_id = 100
    
    # Setup staging with previews
    staging_text_key = "staging/#{staging_upload_id}/text/concatenated.txt"
    staging_pages_key = "staging/#{staging_upload_id}/text/pages.jsonl"
    staging_metrics_key = "staging/#{staging_upload_id}/metrics.json"
    staging_previews_prefix = "staging/#{staging_upload_id}/previews/"
    
    # Create staging files
    File.mkdir_p!(Path.join(temp_storage_root, "staging/#{staging_upload_id}/text"))
    File.mkdir_p!(Path.join(temp_storage_root, "staging/#{staging_upload_id}/previews"))
    File.write!(Path.join(temp_storage_root, staging_text_key), "Sample text")
    File.write!(Path.join(temp_storage_root, staging_pages_key), "[]")
    File.write!(Path.join(temp_storage_root, staging_metrics_key), "{}")
    File.write!(Path.join(temp_storage_root, staging_previews_prefix <> "page-0001.png"), "PNG data")
    File.write!(Path.join(temp_storage_root, staging_previews_prefix <> "page-0002.png"), "PNG data")
    
    staging_upload = %{
      staging_upload_id: staging_upload_id,
      source_hash: "abc123",
      original_filename: "test.pdf",
      storage_key: "staging/#{staging_upload_id}/original/test.pdf"
    }
    
    # Create original file
    File.mkdir_p!(Path.join(temp_storage_root, "staging/#{staging_upload_id}/original"))
    File.write!(Path.join(temp_storage_root, staging_upload.storage_key), "Original content")
    
    artifacts = %{
      "text_concat" => staging_text_key,
      "pages_jsonl" => staging_pages_key,
      "metrics" => staging_metrics_key,
      "previews_prefix" => staging_previews_prefix
    }
    
    assert {:ok, promoted_keys} = Storage.promote!(staging_upload, agreement_id, artifacts)
    
    # Verify preview files were promoted
    assert length(promoted_keys.previews) == 2
    assert Enum.all?(promoted_keys.previews, fn key ->
      File.exists?(Path.join(temp_storage_root, key))
    end)
  end
end
