defmodule SamhstnWeb.Router do
  use Phoenix.Router
  import Plug.Conn
  import Phoenix.Controller

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => "default-src 'self'"}
  end

  scope "/", SamhstnWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/:path", PageController, :route
  end
end
