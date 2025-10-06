defmodule Evhlegalchat.Storage do
  @moduledoc """
  Behaviour for file storage operations.
  
  Provides a unified interface for storing, retrieving, and managing files
  regardless of the underlying storage mechanism.
  """

  @callback put(config :: term(), key :: String.t(), source_path :: Path.t()) :: :ok | {:error, term()}
  @callback get(config :: term(), key :: String.t()) :: {:ok, Path.t()} | {:error, term()}
  @callback head(config :: term(), key :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback delete(config :: term(), key :: String.t()) :: :ok | {:error, term()}

  @doc """
  Default implementation using Local storage.
  """
  def new do
    Evhlegalchat.Storage.Local.new()
  end
end
