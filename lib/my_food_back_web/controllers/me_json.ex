defmodule MyFoodBackWeb.MeJSON do
  alias MyFoodBackWeb.AuthJSON

  def show(%{me: me}), do: AuthJSON.camelize(me)
  def error(%{error: error}), do: %{error: AuthJSON.camelize(error)}
end
