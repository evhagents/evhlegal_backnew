defmodule EvhlegalchatWeb.ProxyController do
  use EvhlegalchatWeb, :controller

  @frontend_url "https://evhlegal-front.onrender.com"

  def proxy(conn, %{"path" => path_segments}) do
    # Reconstruct the path from segments
    path = "/" <> Enum.join(path_segments, "/")
    proxy_request(conn, path)
  end

  def proxy(conn, _params) do
    # Handle root path
    proxy_request(conn, "/")
  end

  defp proxy_request(conn, path) do
    # Build the full URL to the frontend
    frontend_url = "#{@frontend_url}#{path}"

    # Forward query parameters if any
    query_string = if conn.query_string != "", do: "?#{conn.query_string}", else: ""
    full_url = "#{frontend_url}#{query_string}"

    # Prepare headers to forward
    headers = build_forward_headers(conn)

    # Make the request to the frontend
    case make_request(conn.method, full_url, headers, conn.body_params) do
      {:ok, response} ->
        handle_response(conn, response)

      {:error, reason} ->
        handle_error(conn, reason)
    end
  end

  defp build_forward_headers(conn) do
    # Forward important headers from the original request
    important_headers = [
      "user-agent",
      "accept",
      "accept-language",
      "accept-encoding",
      "cache-control",
      "pragma",
      "authorization",
      "content-type",
      "x-requested-with",
      "referer"
    ]

    headers =
      important_headers
      |> Enum.map(fn header ->
        case get_req_header(conn, header) do
          [value] -> {header, value}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Add default headers if missing
    headers =
      if not Enum.any?(headers, fn {k, _} -> k == "user-agent" end) do
        [{"user-agent", "EvhLegalChat-Proxy/1.0"} | headers]
      else
        headers
      end

    headers
  end

  defp make_request("GET", url, headers, _body) do
    Req.get(url,
      headers: headers,
      follow_redirects: true,
      max_redirects: 5,
      receive_timeout: 30_000
    )
  end

  defp make_request("POST", url, headers, body) do
    Req.post(url,
      headers: headers,
      json: body,
      follow_redirects: true,
      max_redirects: 5,
      receive_timeout: 30_000
    )
  end

  defp make_request("PUT", url, headers, body) do
    Req.put(url,
      headers: headers,
      json: body,
      follow_redirects: true,
      max_redirects: 5,
      receive_timeout: 30_000
    )
  end

  defp make_request("PATCH", url, headers, body) do
    Req.patch(url,
      headers: headers,
      json: body,
      follow_redirects: true,
      max_redirects: 5,
      receive_timeout: 30_000
    )
  end

  defp make_request("DELETE", url, headers, _body) do
    Req.delete(url,
      headers: headers,
      follow_redirects: true,
      max_redirects: 5,
      receive_timeout: 30_000
    )
  end

  defp make_request(_, url, headers, _body) do
    # Default to GET for unsupported methods
    Req.get(url,
      headers: headers,
      follow_redirects: true,
      max_redirects: 5,
      receive_timeout: 30_000
    )
  end

  defp handle_response(conn, response) do
    # Set response headers
    conn =
      conn
      |> put_resp_header("x-proxy-source", "evhlegal-backend")
      |> put_resp_header("x-proxy-status", "success")

    # Forward important response headers
    important_response_headers = [
      "content-type",
      "cache-control",
      "etag",
      "last-modified",
      "content-encoding",
      "content-length"
    ]

    conn =
      important_response_headers
      |> Enum.reduce(conn, fn header, acc ->
        case response.headers[header] do
          nil -> acc
          value -> put_resp_header(acc, header, value)
        end
      end)

    # Handle different content types
    content_type = response.headers["content-type"] || "text/html"

    cond do
      String.contains?(content_type, "application/json") ->
        conn
        |> put_resp_content_type("application/json")
        |> json(response.body)

      String.contains?(content_type, "text/") ->
        conn
        |> put_resp_content_type(content_type)
        |> text(response.body)

      String.contains?(content_type, "image/") ->
        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, response.body)

      String.contains?(content_type, "application/javascript") or
          String.contains?(content_type, "text/javascript") ->
        conn
        |> put_resp_content_type("application/javascript")
        |> text(response.body)

      String.contains?(content_type, "text/css") ->
        conn
        |> put_resp_content_type("text/css")
        |> text(response.body)

      true ->
        conn
        |> put_resp_content_type("text/html")
        |> html(response.body)
    end
  end

  defp handle_error(conn, reason) do
    conn
    |> put_status(:bad_gateway)
    |> put_resp_header("x-proxy-source", "evhlegal-backend")
    |> put_resp_header("x-proxy-status", "error")
    |> json(%{
      error: "Failed to proxy request to frontend",
      reason: inspect(reason),
      timestamp: DateTime.utc_now()
    })
  end
end
