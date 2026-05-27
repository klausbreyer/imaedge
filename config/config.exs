# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :imaedge,
  ecto_repos: [Imaedge.Repo],
  generators: [timestamp_type: :utc_datetime]

config :imaedge, Oban,
  repo: Imaedge.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [ingest: 2]

config :imaedge, :uploads,
  chunk_size: 1_048_576,
  chunk_read_timeout: :timer.minutes(2),
  tmp_dir: "tmp/uploads"

config :imaedge, :object_storage,
  adapter: Imaedge.Storage.Local,
  root: "priv/static/objects",
  public_path: "/objects"

# Configure the endpoint
config :imaedge, ImaedgeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ImaedgeWeb.ErrorHTML, json: ImaedgeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Imaedge.PubSub,
  live_view: [signing_salt: "56EErk0/"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  imaedge: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  imaedge: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
