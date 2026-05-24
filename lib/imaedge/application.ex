defmodule Imaedge.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ImaedgeWeb.Telemetry,
      Imaedge.Repo,
      {Oban, Application.fetch_env!(:imaedge, Oban)},
      {DNSCluster, query: Application.get_env(:imaedge, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Imaedge.PubSub},
      # Start a worker by calling: Imaedge.Worker.start_link(arg)
      # {Imaedge.Worker, arg},
      # Start to serve requests, typically the last entry
      ImaedgeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Imaedge.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ImaedgeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
