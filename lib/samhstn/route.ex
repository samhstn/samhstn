defmodule Samhstn.Route do
  @moduledoc """
  This module keeps track of the routes defined in a routes.json file.
  We will fetch the route if it doesn't exist in our cache, or serve from our cache if it does.
  We run background processes to check if we need to update our routes data.
  If the route has been recently updated or visited, we will poll more regularly for changes.
  We implement a cache update backoff for routes which aren't active and for updates to all of our routes.
  """

  use GenServer
  require Logger
  alias Samhstn.Route

  @route Application.get_env(:samhstn, :route)

  @type state :: {Route.Data.t(), [Route.Ref.t()]}

  @spec get(Route.Ref.path()) :: {:ok, Route.Ref.t()} | {:error, String.t() | :not_found}
  def get(path) do
    GenServer.cast(__MODULE__, :get_routes_data)
    GenServer.call(__MODULE__, {:get, path})
  end

  @spec start_link(map) :: {:ok, pid}
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl GenServer
  @callback init(any()) :: {:ok, state}
  def init(_opts) do
    routes_data = %Route.Data{body: json} = @route.get_routes_data!()
    routes = json |> Jason.decode!() |> Enum.map(&Route.Ref.from_map/1)

    {:ok, {routes_data, routes}}
  end

  @impl GenServer
  @callback handle_call({:get, Route.Ref.path()}, pid, state) ::
              {:reply, {:ok, Route.Ref.t()} | {:error, String.t() | :not_found}, state}
  def handle_call({:get, path}, _from, {routes_data, routes} = state) do
    with nil <- Enum.find(routes, fn %Route.Ref{path: p} -> p == path end) do
      {:reply, {:error, :not_found}, state}
    else
      %Route.Ref{data: %Route.Data{}} = route_ref ->
        GenServer.cast(__MODULE__, {:get, route_ref})

        {:reply, {:ok, route_ref}, state}

      %Route.Ref{} = route_ref ->
        new_routes = @route.get_new_routes!(route_ref, routes)
        new_route_ref = Enum.find(new_routes, fn r -> r.path == route_ref.path end)

        {:reply, {:ok, new_route_ref}, {routes_data, new_routes}}
    end
  end

  @impl GenServer
  @callback handle_cast({:get, Route.Ref.t()}, state) :: {:noreply, state}
  def handle_cast({:get, route_ref}, {routes_data, routes}) do
    {:noreply, {routes_data, @route.get_new_routes!(routes, route_ref)}}
  end

  def handle_cast(:get_routes_data, {routes_data, routes}) do
    {:noreply, @route.get_new_routes_data_and_routes!(routes_data, routes)}
  end

  defp check_updates_log(path, routes) do
    longest_path_length =
      ["routes.json" | Enum.map(routes, & &1.path)]
      |> Enum.map(&String.length/1)
      |> Enum.max()

    path = String.pad_trailing(path, longest_path_length)
    date = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Logger.info("#{path}:#{date}:Checking for updates.")
  end

  @impl GenServer
  @callback handle_info({:check, Route.Ref.path()}, state) :: {:noreply, state}
  def handle_info({:check, path}, {routes_data, routes}) do
    check_updates_log(path, routes)

    route_ref = Enum.find(routes, fn route -> route.path == path end)

    {:noreply, {routes_data, @route.check_new_routes!(routes, route_ref)}}
  end

  def handle_info(:check_routes_data, {routes_data, routes}) do
    check_updates_log("routes.json", routes)

    {:noreply, @route.check_new_routes_data_and_routes!(routes_data, routes)}
  end

  @spec schedule_routes_data_check(integer, pid) :: reference
  def schedule_routes_data_check(ms, pid \\ self()) do
    Process.send_after(pid, :check_routes_data, ms)
  end

  @spec schedule_check(Route.Ref.path(), integer) :: reference
  def schedule_check(path, ms, pid \\ self()) do
    Process.send_after(pid, {:check, path}, ms)
  end
end
