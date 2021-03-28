defmodule SamhstnWeb.PageController do
  use SamhstnWeb, :controller

  alias Samhstn.Route

  @spec index(Plug.Conn.t(), map) :: Plug.Conn.t()
  def index(conn, _params) do
    render(conn, "index.html")
  end

  @spec route(Plug.Conn.t(), map) :: Plug.Conn.t()
  # marked as a false positive as we trust the
  # html data coming through from our routes.json file.
  # sobelow_skip ["XSS.HTML"]
  def route(conn, %{"path" => path}) do
    case Route.get(path) do
      {:ok, %Route.Ref{type: :json, data: %{body: body}}} ->
        json(conn, body)

      {:ok, %Route.Ref{type: :text, data: %{body: body}}} ->
        text(conn, body)

      {:ok, %Route.Ref{type: :html, data: %{body: body}}} ->
        html(conn, body)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> put_view(SamhstnWeb.ErrorView)
        |> render("404.html")

      {:error, _error} ->
        conn
        |> put_status(500)
        |> put_view(SamhstnWeb.ErrorView)
        |> render("500.html")
    end
  end
end
