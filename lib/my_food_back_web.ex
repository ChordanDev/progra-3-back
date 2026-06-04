defmodule MyFoodBackWeb do
  @moduledoc """
  The entrypoint for defining the API web interface.

  This can be used in your application as:

      use MyFoodBackWeb, :controller
      use MyFoodBackWeb, :router

  The definitions below will be executed for every controller, router,
  channel, etc., so keep them short and focused on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions below. Instead, define
  additional modules and import those modules here.
  """

  def router do
    quote do
      use Phoenix.Router, helpers: false

      # Import common connection and controller functions to use in pipelines
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      use Gettext, backend: MyFoodBackWeb.Gettext

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: MyFoodBackWeb.Endpoint,
        router: MyFoodBackWeb.Router,
        statics: []
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/router/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
