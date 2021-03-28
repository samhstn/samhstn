defmodule Samhstn.Route.InMemory do
  @moduledoc """
  In memory implementation for fetching routes data.
  We don't read from files or send http requests here.
  """
  use Samhstn.Route.Data

  @spec fetch_body(Route.Ref.t()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch_body(%Route.Ref{source: :s3, path: "routes.json"}) do
    body =
      Jason.encode!([
        %{
          path: "vimrc",
          type: :text,
          source: :url,
          ref: "https://raw.githubusercontent.com/samhstn/my-config/master/.vimrc"
        }
      ])

    {:ok, body}
  end

  def fetch_body(%Route.Ref{source: :url, path: "vimrc"}) do
    body = """
    syntax enable

    set number ignorecase smartcase incsearch autoindent
    """

    {:ok, body}
  end

  def fetch_body(%{path: "dead_link"} = _route_ref) do
    {:error, "dead_link"}
  end
end
