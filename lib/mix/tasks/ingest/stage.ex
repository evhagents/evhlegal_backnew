defmodule Mix.Tasks.Ingest.Stage do
  @moduledoc """
  Staging files manually for ingestion testing.
  
  ## Usage
  
      mix ingest:stage --path path/to/file.pdf
      
  ## Examples
  
      mix ingest:stage --path test/fixtures/sample.pdf
      mix ingest:stage --path tmp/nda_template.docx
  """

  use Mix.Task
  require Logger
  
  alias Evhlegalchat.Ingest.StagingService

  @switches [
    path: :string,
    help: :boolean
  ]

  @aliases [
    p: :path,
    h: :help
  ]

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    cond do
      opts[:help] ->
        print_help()
        System.halt(0)
        
      !opts[:path] ->
        Mix.shell().error("Error: --path is required")
        print_help()
        System.halt(1)
        
      !File.exists?(opts[:path]) ->
        Mix.shell().error("Error: File '#{opts[:path]}' does not exist")
        System.halt(1)
        
      true ->
        stage_file(opts[:path])
    end
  end

  defp stage_file(file_path) do
    Mix.shell().info("Processing file: #{file_path}")
    
    # Start required applications
    Mix.Task.run("app.start")
    
    filename = Path.basename(file_path)
    
    Logger.info("Manual staging requested", file_path: file_path, filename: filename)
    
    case StagingService.stage_upload(file_path, filename) do
      {:ok, staging_upload} ->
        print_success(staging_upload)
      {:error, reason} ->
        Mix.shell().error("Failed to stage file: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp print_success(staging_upload) do
    Mix.shell().info("""
    ✓ File staged successfully!
    
    Staging Upload ID: #{staging_upload.staging_upload_id}
    Storage Key: #{staging_upload.storage_key}
    Source Hash: #{staging_upload.source_hash}
    Content Type: #{staging_upload.content_type_detected}
    Original Filename: #{staging_upload.original_filename}
    File Size: #{humanize_size(staging_upload.byte_size)}
    Status: #{staging_upload.status}
    Scan Status: #{staging_upload.scan_status}
    """)
  end

  defp print_help do
    Mix.shell().info("""
    #{@moduledoc}
    
    ## Options
    
      --path, -p    Path to the file to stage (required)
      --help, -h    Show this help message
      
    ## Examples
    
      mix ingest:stage --path test/fixtures/sample.pdf
      mix ingest:stage --path /path/to/document.docx
    """)
  end

  defp humanize_size(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} B"
      bytes < 1024 * 1024 -> "#{round(bytes / 1024)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{round(bytes / (1024 * 1024))} MB"
      true -> "#{round(bytes / (1024 * 1024 * 1024))} GB"
    end
  end
end
