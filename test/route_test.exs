defmodule Samhstn.RouteTest do
  use ExUnit.Case, async: true

  alias Samhstn.Route

  setup do
    {:ok, pid} = Route.start_link([])

    routes_body =
      Jason.encode!([
        %{
          path: "vimrc",
          type: :text,
          source: :url,
          ref: "https://raw.githubusercontent.com/samhstn/my-config/master/.vimrc"
        }
      ])

    routes = routes_body |> Jason.decode!() |> Enum.map(&Route.Ref.from_map/1)
    backoff = Application.get_env(:samhstn, :route_backoff)

    now = NaiveDateTime.utc_now()
    yesterday = now |> NaiveDateTime.add(-:timer.hours(24))
    recently = now |> NaiveDateTime.add(-div(backoff[:min], 2))

    [
      pid: pid,
      routes_body: routes_body,
      routes: routes,
      yesterday: yesterday,
      recently: recently,
      now: now
    ]
    |> Keyword.merge(backoff)
  end

  test "get/1 returns path data" do
    assert {:ok, %Route.Ref{data: %Route.Data{body: body}, path: "vimrc", type: :text}} =
             Route.get("vimrc")

    assert body =~ "syntax enable"
  end

  test "stores initial routes data and routes after calling get/1", %{
    pid: pid,
    routes_body: routes_body,
    routes: routes
  } do
    assert {%Route.Data{body: ^routes_body}, ^routes} = :sys.get_state(pid)

    assert {:ok, _route_ref} = Route.get("vimrc")

    assert {%Route.Data{body: ^routes_body}, [%Route.Ref{data: %Route.Data{body: route_body}}]} =
             :sys.get_state(pid)

    assert route_body =~ "syntax enable"
  end

  test "get/1 with no update to route data and no recent request", %{
    pid: pid,
    routes_body: routes_body,
    yesterday: yesterday,
    now: now,
    max: max
  } do
    timer = Route.schedule_routes_data_check(max)

    :sys.replace_state(pid, fn {routes_data, routes} ->
      Process.cancel_timer(routes_data.timer)

      {
        %Route.Data{
          body: routes_body,
          fetched_at: yesterday,
          updated_at: yesterday,
          requested_at: yesterday,
          next_update_seconds: max,
          timer: timer
        },
        routes
      }
    end)

    {:ok, _route_ref} = Route.get("vimrc")

    assert {
             %Route.Data{
               body: ^routes_body,
               updated_at: ^yesterday,
               fetched_at: fetched_at,
               requested_at: requested_at,
               next_update_seconds: ^max,
               timer: ^timer
             },
             [%Route.Ref{}]
           } = :sys.get_state(pid)

    assert NaiveDateTime.diff(now, requested_at) == 0
    assert NaiveDateTime.diff(now, fetched_at) == 0
  end

  test "get/1 with recent request", %{pid: pid, recently: recently, now: now, max: max} do
    timer = Route.schedule_routes_data_check(max)

    :sys.replace_state(pid, fn {routes_data, routes} ->
      Process.cancel_timer(routes_data.timer)

      {
        %Route.Data{
          body: "[]",
          updated_at: recently,
          fetched_at: recently,
          requested_at: recently,
          next_update_seconds: max,
          timer: timer
        },
        routes
      }
    end)

    {:ok, _route_ref} = Route.get("vimrc")

    assert {
             %Route.Data{
               body: "[]",
               updated_at: ^recently,
               fetched_at: ^recently,
               requested_at: requested_at,
               next_update_seconds: ^max,
               timer: ^timer
             },
             [%Route.Ref{}]
           } = :sys.get_state(pid)

    refute requested_at == recently
    assert NaiveDateTime.diff(now, requested_at) == 0
  end

  test "get/1 with updates to route data body", %{
    pid: pid,
    yesterday: yesterday,
    now: now,
    max: max,
    min: min,
    routes_body: routes_body
  } do
    timer = Route.schedule_routes_data_check(max)

    :sys.replace_state(pid, fn {routes_data, routes} ->
      Process.cancel_timer(routes_data.timer)

      {
        %Route.Data{
          body: "[]",
          updated_at: yesterday,
          fetched_at: yesterday,
          requested_at: yesterday,
          next_update_seconds: max,
          timer: timer
        },
        routes
      }
    end)

    {:ok, _route_ref} = Route.get("vimrc")

    assert {
             %Route.Data{
               body: ^routes_body,
               updated_at: updated_at,
               fetched_at: fetched_at,
               requested_at: requested_at,
               next_update_seconds: ^min,
               timer: new_timer
             },
             [%Route.Ref{}]
           } = :sys.get_state(pid)

    refute timer == new_timer
    assert NaiveDateTime.diff(now, fetched_at) == 0
    assert NaiveDateTime.diff(now, requested_at) == 0
    assert NaiveDateTime.diff(now, updated_at) == 0
  end

  test "handle_info for :check_routes_data", %{
    pid: pid,
    routes: routes,
    routes_body: routes_body,
    max: max,
    yesterday: yesterday,
    now: now
  } do
    initial_timer = Route.schedule_routes_data_check(max, pid)

    :sys.replace_state(pid, fn {routes_data, routes} ->
      Process.cancel_timer(routes_data.timer)

      {
        %Route.Data{
          body: routes_body,
          fetched_at: yesterday,
          updated_at: yesterday,
          requested_at: yesterday,
          next_update_seconds: max,
          timer: initial_timer
        },
        routes
      }
    end)

    Route.schedule_routes_data_check(0, pid)

    Process.sleep(100)

    assert {
             %Route.Data{
               body: ^routes_body,
               updated_at: updated_at,
               fetched_at: fetched_at,
               requested_at: requested_at,
               timer: new_timer,
               next_update_seconds: next_update_seconds
             },
             ^routes
           } = :sys.get_state(pid)

    refute new_timer == initial_timer
    assert next_update_seconds == max
    assert NaiveDateTime.diff(updated_at, now, :microsecond) < 0
    assert NaiveDateTime.diff(fetched_at, now, :microsecond) > 0
    assert NaiveDateTime.diff(requested_at, now, :microsecond) < 0
  end

  test "handle_info for :check_routes_data with new routes_body", %{
    pid: pid,
    routes: routes,
    routes_body: routes_body,
    min: min,
    now: now
  } do
    :sys.replace_state(pid, fn {routes_data, routes} ->
      {%{routes_data | body: "[]"}, routes}
    end)

    Route.schedule_routes_data_check(0, pid)

    Process.sleep(100)

    assert {
             %Route.Data{
               body: ^routes_body,
               next_update_seconds: next_update_seconds,
               updated_at: updated_at,
               fetched_at: fetched_at,
               requested_at: requested_at
             },
             ^routes
           } = :sys.get_state(pid)

    assert next_update_seconds == min
    assert NaiveDateTime.diff(updated_at, now, :microsecond) > 0
    assert NaiveDateTime.diff(fetched_at, now, :microsecond) > 0
    assert NaiveDateTime.diff(requested_at, now, :microsecond) < 0
  end

  test "handle_info for :check", %{pid: pid, max: max, now: now, yesterday: yesterday} do
    vimrc = """
    syntax enable

    set number ignorecase smartcase incsearch autoindent
    """

    initial_timer = Route.schedule_check("vimrc", 1000, pid)

    :sys.replace_state(pid, fn {routes_data, routes} ->
      new_vimrc_data = %Route.Data{
        body: vimrc,
        fetched_at: yesterday,
        updated_at: yesterday,
        requested_at: yesterday,
        next_update_seconds: max,
        timer: initial_timer
      }

      new_routes =
        Enum.map(routes, fn route ->
          if route.path == "vimrc" do
            %{route | data: new_vimrc_data}
          else
            route
          end
        end)

      {routes_data, new_routes}
    end)

    Route.schedule_check("vimrc", 0, pid)

    Process.sleep(100)

    assert {
             _route_data,
             [
               %Route.Ref{
                 data: %Route.Data{
                   body: ^vimrc,
                   fetched_at: fetched_at,
                   updated_at: ^yesterday,
                   requested_at: ^yesterday,
                   next_update_seconds: ^max,
                   timer: new_timer
                 },
                 path: "vimrc"
               }
             ]
           } = :sys.get_state(pid)

    refute new_timer == initial_timer
    assert NaiveDateTime.diff(fetched_at, now) == 0
  end

  test "handle_info for :check with new individual route data", %{
    yesterday: yesterday,
    pid: pid,
    max: max,
    min: min,
    now: now
  } do
    initial_timer = Route.schedule_check("vimrc", max, pid)

    :sys.replace_state(pid, fn {routes_data, routes} ->
      new_vimrc_data = %Route.Data{
        body: "syntax disable",
        fetched_at: yesterday,
        updated_at: yesterday,
        requested_at: yesterday,
        next_update_seconds: max,
        timer: initial_timer
      }

      new_routes =
        Enum.map(routes, fn route ->
          if route.path == "vimrc" do
            %{route | data: new_vimrc_data}
          else
            route
          end
        end)

      {routes_data, new_routes}
    end)

    Route.schedule_check("vimrc", 0, pid)

    Process.sleep(100)

    assert {
             _route_data,
             [
               %Route.Ref{
                 data: %Route.Data{
                   body: vimrc,
                   fetched_at: fetched_at,
                   updated_at: updated_at,
                   requested_at: ^yesterday,
                   next_update_seconds: ^min,
                   timer: new_timer
                 },
                 path: "vimrc"
               }
             ]
           } = :sys.get_state(pid)

    assert vimrc =~ "syntax enable"
    refute new_timer == initial_timer
    assert NaiveDateTime.diff(fetched_at, now) == 0
    assert NaiveDateTime.diff(updated_at, now) == 0
  end
end
