defmodule MyFoodBack.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyFoodBackWeb.Telemetry,
      MyFoodBack.Repo,
      {DNSCluster, query: Application.get_env(:my_food_back, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MyFoodBack.PubSub},
      # Start a worker by calling: MyFoodBack.Worker.start_link(arg)
      # {MyFoodBack.Worker, arg},
      # Start to serve requests, typically the last entry
      MyFoodBackWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MyFoodBack.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MyFoodBackWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
