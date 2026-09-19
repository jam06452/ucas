# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ucas,
  ecto_repos: [Ucas.Repo],
  generators: [timestamp_type: :utc_datetime]

# Index course study options from Postgres into Typesense on boot when the
# collection is missing or empty. Disable to manage indexing out-of-band
# (e.g. via a deploy step running `mix ucas.search.reindex`).
config :ucas, search_bootstrap: true

# Configure the endpoint
config :ucas, UcasWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: UcasWeb.ErrorHTML, json: UcasWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ucas.PubSub,
  live_view: [signing_salt: "PHX7XRqU"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :ucas, Ucas.Mailer, adapter: Swoosh.Adapters.Local

# Configure the Typesense connection used by `ex_typesense`.
# The local instance is provided by `docker-compose.yml`; production
# overrides these values from environment variables in `runtime.exs`.
config :open_api_typesense,
  api_key: "xyz",
  host: "localhost",
  port: 8108,
  scheme: "http"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ucas: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  ucas: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
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
