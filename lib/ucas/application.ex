defmodule Ucas.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      UcasWeb.Telemetry,
      Ucas.Repo,
      {DNSCluster, query: Application.get_env(:ucas, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ucas.PubSub},
      # Start a worker by calling: Ucas.Worker.start_link(arg)
      # {Ucas.Worker, arg},
      # Start to serve requests, typically the last entry
      UcasWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ucas.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    UcasWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
