defmodule Evhlegalchat.Ingest.AV do
  @moduledoc """
  Antivirus scanning module for uploaded files.
  
  Currently provides a stub implementation that can be extended
  to integrate with ClamAV or other scanning engines.
  """

  require Logger

  @doc """
  Scan a file for malware threats.
  
  Returns:
  - :clean - File is safe
  - :infected - File contains malware
  - :skipped - Scanning was not performed
  """
  def scan(file_path) when is_binary(file_path) do
    if enabled?() do
      perform_scan(file_path)
    else
      Logger.debug("Antivirus scanning disabled, marking as skipped")
      :skipped
    end
  end

  @doc """
  Check if antivirus scanning is enabled.
  """
  def enabled? do
    Application.get_env(:evhlegalchat, __MODULE__, [])
    |> Keyword.get(:enabled, false)
  end

  # Private functions

  defp perform_scan(file_path) do
    case get_scanner_config() do
      nil ->
        Logger.warning("Antivirus scanning enabled but no scanner configured")
        :skipped
      config ->
        scan_with_config(file_path, config)
    end
  end

  defp get_scanner_config do
    Application.get_env(:evhlegalchat, __MODULE__, [])
    |> Keyword.get(:scanner)
  end

  defp scan_with_config(file_path, :clamd) do
    case :os.type() do
      {:unix, _} ->
        scan_with_clamd(file_path)
      {:win32, _} ->
        Logger.warning("ClamAV not available on Windows, skipping scan")
        :skipped
    end
  end

  defp scan_with_config(_file_path, config) do
    Logger.warning("Unknown scanner configuration: #{inspect(config)}")
    :skipped
  end

  defp scan_with_clamd(file_path) do
    try do
      port_command = "clamdscan --no-summary --infected #{file_path}"
      
      case System.cmd("/bin/sh", ["-c", port_command], stderr_to_stdout: true) do
        {_output, exit_status} when exit_status == 0 ->
          :clean
        {output, _exit_status} ->
          Logger.warning("ClamAV detected infection: #{output}")
          :infected
      end
    rescue
      error ->
        Logger.error("ClamAV scan failed: #{inspect(error)}")
        :skipped
    end
  end
end
