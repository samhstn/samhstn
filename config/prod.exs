import Config

config :samhstn, SamhstnWeb.Endpoint,
  force_ssl: [rewrite_on: [:x_forwarded_proto]],
  load_from_system_env: true,
  cache_static_manifest: "priv/static/cache_manifest.json",
  server: true

config :logger, level: :info

config :samhstn, :route, Samhstn.Route.Client

config :samhstn, :route_backoff,
  min: :timer.seconds(3),
  max: :timer.minutes(30),
  multiplier: 2

config :ex_aws, region: "eu-west-1"
