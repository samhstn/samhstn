defmodule Samhstn.Route.Sandbox do
  @moduledoc """
  Provides simple routing for urls according the content of priv/assets,
  behaves as if priv/assets was our s3 bucket.
  """
  use Samhstn.Route.Data

  alias Route.Client

  @impl Route.Data
  def fetch_body(%Route.Ref{source: :url} = route_ref), do: Client.fetch_body(route_ref)

  # marked as a false positive as the sandbox is only used in development
  # sobelow_skip ["Traversal.FileModule"]
  def fetch_body(%Route.Ref{source: :s3} = route_ref) do
    with %{object: object} <- Route.Ref.parse_s3_ref(route_ref.ref),
         {:ok, body} <- File.read(Path.join([File.cwd!(), "priv/assets", object])) do
      {:ok, body}
    else
      {:error, :enoent} ->
        {:error, "file does not exist"}
    end
  end
end
