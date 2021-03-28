import Config

config :samhstn, SamhstnWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true

config :logger, :console, format: "[$level] $message\n"

# set higher stacktrace depth in dev for easier debugging
config :phoenix, :stacktrace_depth, 20

# initialize plugs at runtime for faster dev compilation
config :phoenix, :plug_init_mode, :runtime

config :samhstn, :route, Samhstn.Route.Sandbox

config :samhstn, :route_backoff,
  min: 100,
  max: :timer.seconds(20),
  multiplier: 2

config :ex_aws,
  secret_access_key: [{:awscli, "samhstn-admin", 30}],
  access_key_id: [{:awscli, "samhstn-admin", 30}],
  region: "eu-west-1",
  awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleCredentialsAdapter
