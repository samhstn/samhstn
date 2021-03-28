defmodule Samhstn.Route.Data do
  @moduledoc """
  Defines a struct and the required functions for fetching our route data.
  These functions have different implementations depending on environment, but the same behaviour.
  """
  @enforce_keys [:body, :fetched_at, :updated_at, :requested_at, :next_update_seconds, :timer]
  defstruct [:body, :fetched_at, :updated_at, :requested_at, :next_update_seconds, :timer]

  alias Samhstn.Route

  @type t() :: %__MODULE__{
          body: String.t(),
          fetched_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t(),
          requested_at: NaiveDateTime.t(),
          next_update_seconds: integer,
          timer: reference
        }

  @doc """
  Fetches the body for a given route ref.

  This function needs to be defined where this module macro is used.
  """
  @callback fetch_body(Route.Ref.t()) :: {:ok, String.t()} | {:error, String.t()}

  defmacro __using__(_) do
    quote do
      alias Samhstn.Route

      # This @behaviour throws a warning if the @callback functions aren't defined
      # where this is used.
      @behaviour Route.Data

      @assets_bucket Application.fetch_env!(:samhstn, :assets_bucket)
      @backoff Application.fetch_env!(:samhstn, :route_backoff)

      @spec get_routes_data!() :: Route.Data.t()
      def get_routes_data!(), do: get_routes_data!(nil)

      @doc """
      Fetches the routes data and schedules route updates.
      """
      @spec get_routes_data!(Route.Data.t() | nil) :: Route.Data.t()
      def get_routes_data!(routes_data) do
        now = NaiveDateTime.utc_now()
        min = @backoff[:min]

        if routes_data && NaiveDateTime.diff(now, routes_data.fetched_at) < min do
          %{routes_data | requested_at: now}
        else
          case fetch_body(%Route.Ref{
                 path: "routes.json",
                 ref: {@assets_bucket, "routes.json"},
                 source: :s3,
                 type: :json
               }) do
            {:ok, body} ->
              cond do
                is_nil(routes_data) or routes_data.body != body ->
                  if not is_nil(routes_data) && routes_data.body != body do
                    cancel_timer(routes_data)
                  end

                  %Route.Data{
                    body: body,
                    updated_at: now,
                    fetched_at: now,
                    requested_at: now,
                    next_update_seconds: min,
                    timer: Route.schedule_routes_data_check(min)
                  }

                routes_data.body == body ->
                  %{routes_data | fetched_at: now, requested_at: now}
              end

            {:error, error} ->
              throw(error)
          end
        end
      end

      @doc """
      Populates the :data field in our route ref.
      This contains metadata as well as scheduling an update for this route.
      Overwrites the `:data` attribute of the given Route.Ref, best to use when this is `nil`.
      """
      @spec get(Route.Ref.t()) :: {:ok, Route.Ref.t()} | {:error, String.t()}
      def get(%Route.Ref{path: path} = route_ref) do
        now = NaiveDateTime.utc_now()
        min = @backoff[:min]

        case fetch_body(route_ref) do
          {:ok, body} ->
            data = %Route.Data{
              body: body,
              updated_at: now,
              fetched_at: now,
              requested_at: now,
              next_update_seconds: min,
              timer: Route.schedule_check(path, min)
            }

            {:ok, %{route_ref | data: data}}

          {:error, error} ->
            {:error, error}
        end
      end

      @spec get!(Route.Ref.t()) :: Route.Ref.t()
      def get!(route_ref = %Route.Ref{}) do
        case get(route_ref) do
          {:ok, route_ref} ->
            route_ref

          {:error, error} ->
            throw(error)
        end
      end

      @doc """
      Updates the given route ref in our list of routes and re-schedules our route ref timer.
      """
      @spec new_routes(Route.Ref.t(), [Route.Ref.t()]) :: [Route.Ref.t()]
      def new_routes(new_route_ref, routes) do
        Enum.map(routes, fn route ->
          if route.path == new_route_ref.path do
            new_route_ref
          else
            route
          end
        end)
      end

      @spec get_new_routes!(Route.Ref.t(), [Route.Ref.t()]) :: [Route.Ref.t()]
      def get_new_routes!(route_ref, routes) do
        route_ref
        |> get!()
        |> new_routes(routes)
      end

      @spec routes_from_body!(String.t(), [Route.Ref.t()]) :: [Route.Ref.t()]
      defp routes_from_body!(body, routes) do
        body
        |> Jason.decode!()
        |> Enum.map(&Route.Ref.from_map/1)
        |> Enum.map(fn %Route.Ref{path: path, ref: ref, source: source, type: type} = route_ref ->
          with %Route.Ref{ref: ^ref, source: ^source, type: ^type} = old_route_ref <-
                 Enum.find(routes, fn r -> r.path == path end) do
            # we look to keep the route_ref data attribute as the route doesn't need to be updated.
            old_route_ref
          else
            # we remove the :data attribute as we have updated the route,
            # so it will need to be fetched again
            _ -> route_ref
          end
        end)
      end

      @spec get_new_routes_data_and_routes!(Route.Data.t() | nil, [Route.Ref.t()]) ::
              Route.state()
      def get_new_routes_data_and_routes!(routes_data, routes) do
        %Route.Data{body: new_body} = new_routes_data = get_routes_data!(routes_data)

        if is_nil(routes_data) or routes_data.body == new_body do
          {new_routes_data, routes}
        else
          {new_routes_data, routes_from_body!(new_body, routes)}
        end
      end

      @spec check_new_routes!([Route.Ref.t()], Route.Ref.t()) :: [Route.Ref.t()]
      def check_new_routes!(routes, %Route.Ref{data: route_data} = route_ref) do
        case fetch_body(route_ref) do
          {:ok, body} ->
            now = NaiveDateTime.utc_now()

            cancel_timer(route_data)

            new_route_ref_data = %Route.Data{
              body: body,
              fetched_at: now,
              updated_at:
                if route_data.body == body do
                  route_data.updated_at
                else
                  now
                end,
              requested_at: route_data.requested_at,
              next_update_seconds: next_update_seconds(route_data, body),
              timer: Route.schedule_check(route_ref.path, next_update_seconds(route_data, body))
            }

            Enum.map(routes, fn rr ->
              if rr.path == route_ref.path do
                %{rr | data: new_route_ref_data}
              else
                rr
              end
            end)

          {:error, error} ->
            throw(error)
        end
      end

      @spec check_new_routes_data_and_routes!(Route.Data.t(), [Route.Ref.t()]) :: Route.state()
      def check_new_routes_data_and_routes!(routes_data, routes) do
        now = NaiveDateTime.utc_now()

        cancel_timer(routes_data)

        case fetch_body(%Route.Ref{
               path: "routes.json",
               ref: {@assets_bucket, "routes.json"},
               source: :s3,
               type: :json
             }) do
          {:ok, body} ->
            routes =
              if routes_data.body == body do
                routes_from_body!(body, routes)
              else
                routes
              end

            routes_data = %Route.Data{
              body: body,
              updated_at:
                if routes_data.body == body do
                  routes_data.updated_at
                else
                  now
                end,
              fetched_at: now,
              requested_at: routes_data.requested_at,
              next_update_seconds: next_update_seconds(routes_data, body),
              timer: Route.schedule_routes_data_check(next_update_seconds(routes_data, body))
            }

            {routes_data, routes}

          {:error, error} ->
            throw(error)
        end
      end

      defp cancel_timer(%Route.Data{timer: timer}) when is_nil(timer), do: nil

      defp cancel_timer(%Route.Data{timer: timer}) do
        if Process.read_timer(timer) do
          Process.cancel_timer(timer)
        end
      end

      defp next_update_seconds(route_data, body) do
        [min: min, max: max, multiplier: multiplier] = @backoff

        if route_data.body == body do
          min(route_data.next_update_seconds * multiplier, max)
        else
          min
        end
      end
    end
  end
end
