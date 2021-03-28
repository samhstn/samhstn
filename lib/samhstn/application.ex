defmodule Samhstn.Application do
  use Application

  @children Application.get_env(:samhstn, :children)

  def start(_type, _args) do
    Supervisor.start_link(
      @children,
      strategy: :one_for_one,
      name: Samhstn.Supervisor
    )
  end
end
