defmodule Samhstn.Route.Ref do
  alias Samhstn.Route

  @enforce_keys [:path, :type, :source, :ref]
  defstruct [:path, :type, :source, :ref, :data]

  @type path :: String.t()
  @type ref() :: String.t() | {String.t(), String.t()}
  @type source() :: :s3 | :url
  @type type() :: :html | :json | :text
  @type t() :: %__MODULE__{
          data: Route.Data.t() | nil,
          path: path,
          ref: ref,
          source: source,
          type: type
        }

  @spec type_to_atom(String.t()) :: type
  defp type_to_atom("html"), do: :html
  defp type_to_atom("json"), do: :json
  defp type_to_atom("text"), do: :text

  @spec source_to_atom(String.t()) :: source
  defp source_to_atom("s3"), do: :s3
  defp source_to_atom("url"), do: :url

  @spec from_map(map) :: t
  def from_map(%{"path" => path, "type" => type, "source" => source, "ref" => ref}) do
    %__MODULE__{path: path, type: type_to_atom(type), source: source_to_atom(source), ref: ref}
  end

  # TODO: gracefully handle strings which don't match
  @spec parse_s3_ref(String.t() | {String.t(), String.t()}) :: map
  def parse_s3_ref("arn:aws:s3:::" <> rest) do
    [bucket | path] = String.split(rest, "/")

    %{bucket: bucket, object: Enum.join(path, "/")}
  end

  def parse_s3_ref({bucket, object}) do
    %{bucket: bucket, object: object}
  end

  @spec clear_data(__MODULE__.t()) :: __MODULE__.t()
  def clear_data(route_ref), do: Map.delete(route_ref, :data)
end
