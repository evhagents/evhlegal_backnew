defmodule Evhlegalchat.Ingest.Extract.Port do
  @moduledoc """
  Supervised Port execution for external command-line tools.
  
  Provides secure, timeout-aware execution of CLI tools with proper
  error handling and resource cleanup.
  """

  require Logger

  @doc """
  Executes a command with arguments and timeout.
  
  ## Options
  
  - `:timeout` - Maximum execution time in milliseconds (default: 30_000)
  - `:cwd` - Working directory for the command
  - `:env` - Environment variables to set
  
  ## Examples
  
      iex> run("pdftotext", ["-layout", "-enc", "UTF-8", "input.pdf", "-"])
      {:ok, "extracted text content..."}
      
      iex> run("nonexistent", ["arg"], timeout: 1000)
      {:error, :timeout}
  """
  def run(cmd_path, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    cwd = Keyword.get(opts, :cwd)
    env = Keyword.get(opts, :env)
    
    Logger.debug("Executing command", cmd: cmd_path, args: args, timeout: timeout)
    
    port_opts = [
      :binary, 
      :exit_status, 
      :stderr_to_stdout
    ]
    
    port_opts = if cwd, do: [{:cd, cwd} | port_opts], else: port_opts
    port_opts = if env, do: [{:env, env} | port_opts], else: port_opts
    
    port = Port.open(
      {:spawn_executable, cmd_path}, 
      port_opts ++ [args: args]
    )
    
    try do
      collect_output(port, "", timeout)
    after
      Port.close(port)
    end
  end

  @doc """
  Runs a command and returns stdout, stderr separately.
  
  Returns `{:ok, {stdout, stderr}}` or `{:error, reason}`.
  """
  def run_split(cmd_path, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    
    port = Port.open(
      {:spawn_executable, cmd_path},
      [:binary, :exit_status, args: args, split: true]
    )
    
    try do
      collect_split_output(port, {"", ""}, timeout)
    after
      Port.close(port)
    end
  end

  @doc """
  Runs a command with file paths, ensuring they're within allowed directories.
  
  Useful for extraction tools that read/write files.
  """
  def run_file_command(cmd_path, args, opts \\ []) do
    # Validate that all file paths in args are within allowed directories
    allowed_dirs = Keyword.get(opts, :allowed_dirs, [System.tmp_dir!()])
    
    file_args = Enum.filter(args, fn arg ->
      Path.type(arg) == :absolute and 
      String.match?(arg, ~r/^[A-Za-z]:\\.*/) == false # Windows paths
    end)
    
    unsafe_files = Enum.reject(file_args, fn file_path ->
      Enum.any?(allowed_dirs, fn dir ->
        String.starts_with?(Path.expand(file_path), Path.expand(dir))
      end)
    end)
    
    if unsafe_files != [] do
      Logger.error("Unsafe file paths detected", paths: unsafe_files)
      {:error, :unsafe_paths}
    else
      run(cmd_path, args, opts)
    end
  end

  @doc """
  Checks if a command is available in the system PATH.
  """
  def command_available?(cmd_path) do
    case cmd_path do
      cmd when is_binary(cmd) ->
        case :os.find_executable(String.to_charlist(cmd)) do
          :false -> false
          _path -> true
        end
      _ -> false
    end
  end

  @doc """
  Gets the version string for a command.
  
  Tries `--version`, `-v`, `--help` in order and extracts version.
  """
  def get_version(cmd_path, version_flags \\ ["--version", "-v"]) do
    Enum.find_value(version_flags, fn flag ->
      case run(cmd_path, [flag], timeout: 5000) do
        {:ok, output} -> extract_version(output)
        {:error, _} -> nil
      end
    end)
  end

  # Private functions

  defp collect_output(port, acc, timeout) do
    receive do
      {^port, {:data, data}} ->
        collect_output(port, acc <> data, timeout)
      {^port, {:exit_status, 0}} ->
        {:ok, acc}
      {^port, {:exit_status, status}} ->
        Logger.warning("Command failed with non-zero exit status", 
          exit_status: status, 
          output: String.slice(acc, 0, 500)  # Truncate output in logs
        )
        {:error, {:exit_status, status, acc}}
    after
      timeout ->
        Logger.error("Command timed out")
        {:error, :timeout}
    end
  end

  defp collect_split_output(port, {stdout_acc, stderr_acc}, timeout) do
    receive do
      {^port, {:data, :stdout, data}} ->
        collect_split_output(port, {stdout_acc <> data, stderr_acc}, timeout)
      {^port, {:data, :stderr, data}} ->
        collect_split_output(port, {stdout_acc, stderr_acc <> data}, timeout)
      {^port, {:exit_status, 0}} ->
        {:ok, {stdout_acc, stderr_acc}}
      {^port, {:exit_status, status}} ->
        Logger.warning("Command failed with non-zero exit status",
          exit_status: status,
          stdout: String.slice(stdout_acc, 0, 200),
          stderr: String.slice(stderr_acc, 0, 200)
        )
        {:error, {:exit_status, status, stdout_acc, stderr_acc}}
    after
      timeout ->
        Logger.error("Command timed out (split)")
        {:error, :timeout}
    end
  end

  defp extract_version(output) do
    # Try to extract version number patterns like "5.3.0", "24.02.0", etc.
    case Regex.run(~r/(\d+\.\d+(?:\.\d+)?)/, output) do
      [version, _] -> version
      _ -> 
        # Fallback to first line if no numeric version found
        output |> String.split("\n") |> List.first() |> String.slice(0, 50)
    end
  end
end
