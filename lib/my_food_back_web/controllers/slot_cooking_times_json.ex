defmodule MyFoodBackWeb.SlotCookingTimesJSON do
  alias MyFoodBackWeb.AuthJSON
  alias MyFoodBackWeb.ErrorRendering

  def show(%{slots: slots}) do
    AuthJSON.camelize(slots)
  end

  def error(%{error: error}), do: %{error: AuthJSON.camelize(ErrorRendering.safe_error(error))}
end
