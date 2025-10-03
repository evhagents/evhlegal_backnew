defmodule Evhlegalchat.OpenRouter do
  @moduledoc """
  OpenRouter API client for chat completions.

  This module provides a simple interface to interact with OpenRouter's API
  for chat completions using various AI models.
  """

  @default_model "x-ai/grok-4-fast:free"

  @doc """
  Sends a chat completion request to OpenRouter API.

  ## Parameters

  - `messages`: List of message maps with "role" and "content" keys
  - `opts`: Keyword list of options
    - `:model` - The model to use
    - `:user_id` - User identifier for abuse detection (defaults to "anonymous")

  ## Examples

      iex> messages = [%{"role" => "user", "content" => "Hello!"}]
      iex> Evhlegalchat.OpenRouter.chat(messages)
      {:ok, "Hello! How can I help you today?"}

  ## Returns

  - `{:ok, content}` - Success with the AI response content
  - `{:error, {status, message}}` - API error with status code and message
  - `{:error, {:unexpected, response}}` - Unexpected response format
  """
  def chat(messages, opts \\ []) do
    config = Application.get_env(:evhlegalchat, :openrouter)
    base_url = config[:base_url]
    api_key = config[:api_key]
    model = Keyword.get(opts, :model, @default_model)

    if is_nil(api_key) or api_key == "" do
      require Logger

      Logger.error(
        "OpenRouter API key not configured. Please set OPENROUTER_API_KEY environment variable."
      )

      {:error,
       {401,
        "OpenRouter API key not configured. Please set OPENROUTER_API_KEY environment variable."}}
    else
      make_request(messages, opts, base_url, api_key, model)
    end
  end

  defp make_request(messages, opts, base_url, api_key, model) do
    require Logger

    body = %{
      "model" => model,
      "messages" => messages,
      # good practice: pass a stable user id for abuse detection
      "user" => Keyword.get(opts, :user_id, "anonymous")
    }

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"content-type", "application/json"},
      # Optional niceties OpenRouter recognizes:
      {"x-title", "EVH Legal Agent"},
      # set your actual app origin in prod
      {"http-referer", "https://evh-legal.local"}
    ]

    req = Req.new(base_url: base_url, url: "/chat/completions", headers: headers)

    Logger.debug("Making OpenRouter API request with model: #{model}")

    with {:ok, %Req.Response{status: 200, body: %{"choices" => [choice | _]}}} <-
           Req.post(req, json: body) do
      content = get_in(choice, ["message", "content"]) || ""
      Logger.debug("OpenRouter API request successful")
      {:ok, content}
    else
      {:ok, %Req.Response{status: status, body: %{"error" => err}}} ->
        error_msg = Map.get(err, "message", "OpenRouter error")
        Logger.error("OpenRouter API error: #{status} - #{error_msg}")
        {:error, {status, error_msg}}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("OpenRouter API unexpected response: #{status} - #{inspect(body)}")
        {:error, {status, "Unexpected response format"}}

      {:error, reason} ->
        Logger.error("OpenRouter API request failed: #{inspect(reason)}")
        {:error, {:network_error, reason}}

      other ->
        Logger.error("OpenRouter API unexpected error: #{inspect(other)}")
        {:error, {:unexpected, other}}
    end
  end
end
