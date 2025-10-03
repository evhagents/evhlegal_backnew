defmodule EvhlegalchatWeb.Router do
  use EvhlegalchatWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug, origin: ["https://evhlegal-front.onrender.com", "http://localhost:3000"]
  end

  pipeline :proxy do
    plug :accepts, ["html", "json", "text", "javascript", "css"]
  end

  # API routes for backend functionality
  scope "/api", EvhlegalchatWeb do
    pipe_through :api

    # Health check endpoint
    get "/health", HealthController, :health

    # Add your API routes here
    # get "/users", UserController, :index
    # post "/chat", ChatController, :create
  end

  # Proxy routes - catch all frontend routes and proxy them
  scope "/", EvhlegalchatWeb do
    pipe_through :proxy
    
    # Catch all routes and proxy them to the frontend
    get "/*path", ProxyController, :proxy
    post "/*path", ProxyController, :proxy
    put "/*path", ProxyController, :proxy
    patch "/*path", ProxyController, :proxy
    delete "/*path", ProxyController, :proxy
  end
end