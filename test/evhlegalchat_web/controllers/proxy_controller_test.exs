defmodule EvhlegalchatWeb.ProxyControllerTest do
  use EvhlegalchatWeb.ConnCase, async: true

  import Mox

  describe "proxy/2" do
    test "proxies GET requests to frontend", %{conn: conn} do
      # Mock the Req request
      expect(ReqMock, :get, fn url, opts ->
        assert url == "https://evhlegal-front.onrender.com/"
        assert Keyword.get(opts, :follow_redirects) == true

        {:ok,
         %Req.Response{
           status: 200,
           headers: %{"content-type" => "text/html"},
           body: "<html><body>Test</body></html>"
         }}
      end)

      conn = get(conn, ~p"/")

      assert response(conn, 200) =~ "Test"
      assert get_resp_header(conn, "x-proxy-source") == ["evhlegal-backend"]
      assert get_resp_header(conn, "x-proxy-status") == ["success"]
    end

    test "proxies requests with path segments", %{conn: conn} do
      expect(ReqMock, :get, fn url, _opts ->
        assert url == "https://evhlegal-front.onrender.com/users"

        {:ok,
         %Req.Response{
           status: 200,
           headers: %{"content-type" => "text/html"},
           body: "<html><body>Users Page</body></html>"
         }}
      end)

      conn = get(conn, ~p"/users")

      assert response(conn, 200) =~ "Users Page"
    end

    test "handles proxy errors gracefully", %{conn: conn} do
      expect(ReqMock, :get, fn _url, _opts ->
        {:error, :timeout}
      end)

      conn = get(conn, ~p"/")

      assert json_response(conn, 502)["error"] == "Failed to proxy request to frontend"
      assert get_resp_header(conn, "x-proxy-source") == ["evhlegal-backend"]
      assert get_resp_header(conn, "x-proxy-status") == ["error"]
    end

    test "forwards query parameters", %{conn: conn} do
      expect(ReqMock, :get, fn url, _opts ->
        assert url == "https://evhlegal-front.onrender.com/search?q=test"

        {:ok,
         %Req.Response{
           status: 200,
           headers: %{"content-type" => "text/html"},
           body: "<html><body>Search Results</body></html>"
         }}
      end)

      conn = get(conn, ~p"/search?q=test")

      assert response(conn, 200) =~ "Search Results"
    end

    test "handles JSON responses", %{conn: conn} do
      expect(ReqMock, :get, fn _url, _opts ->
        {:ok,
         %Req.Response{
           status: 200,
           headers: %{"content-type" => "application/json"},
           body: %{"message" => "Hello World"}
         }}
      end)

      conn = get(conn, ~p"/api/test")

      assert json_response(conn, 200)["message"] == "Hello World"
    end
  end
end
