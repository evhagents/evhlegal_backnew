#!/usr/bin/env elixir

# Simple script to test the proxy functionality
# Run with: elixir scripts/test_proxy.exs

defmodule ProxyTest do
  def run do
    IO.puts("Testing EVH Legal Chat Proxy Setup...")
    IO.puts("=" |> String.duplicate(50))
    
    # Test 1: Check if the server is running
    test_server_connection()
    
    # Test 2: Test proxy to frontend
    test_proxy_request()
    
    # Test 3: Test API endpoint
    test_api_endpoint()
    
    IO.puts("\nProxy test completed!")
  end
  
  defp test_server_connection do
    IO.puts("\n1. Testing server connection...")
    
    case Req.get("http://localhost:4000/", receive_timeout: 5000) do
      {:ok, response} ->
        IO.puts("   ✓ Server is running (Status: #{response.status})")
        if response.headers["x-proxy-source"] do
          IO.puts("   ✓ Proxy headers present")
        end
      {:error, reason} ->
        IO.puts("   ✗ Server connection failed: #{inspect(reason)}")
        IO.puts("   Make sure the server is running with: mix phx.server")
    end
  end
  
  defp test_proxy_request do
    IO.puts("\n2. Testing proxy to frontend...")
    
    case Req.get("http://localhost:4000/users", receive_timeout: 10000) do
      {:ok, response} ->
        IO.puts("   ✓ Proxy request successful (Status: #{response.status})")
        if response.headers["x-proxy-source"] == "evhlegal-backend" do
          IO.puts("   ✓ Proxy source header correct")
        end
        if String.contains?(response.body, "EVH Legal") do
          IO.puts("   ✓ Frontend content received")
        end
      {:error, reason} ->
        IO.puts("   ✗ Proxy request failed: #{inspect(reason)}")
    end
  end
  
  defp test_api_endpoint do
    IO.puts("\n3. Testing API endpoint...")
    
    case Req.get("http://localhost:4000/api/health", receive_timeout: 5000) do
      {:ok, response} ->
        IO.puts("   ✓ API endpoint accessible (Status: #{response.status})")
      {:error, %{status: 404}} ->
        IO.puts("   ! API endpoint not found (expected if not implemented)")
      {:error, reason} ->
        IO.puts("   ✗ API request failed: #{inspect(reason)}")
    end
  end
end

# Run the test
ProxyTest.run()
