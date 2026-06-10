defmodule MyFoodBackWeb.PreferencesJSON do
  alias MyFoodBackWeb.AuthJSON
  alias MyFoodBackWeb.ErrorRendering

  def show(%{preferences: prefs}) do
    %{
      diet: Map.get(prefs, :diet),
      hardRestrictions: Map.get(prefs, :hard_restrictions, []) || [],
      softPreferences: Map.get(prefs, :soft_preferences, []) || []
    }
  end

  def error(%{error: error}), do: %{error: AuthJSON.camelize(ErrorRendering.safe_error(error))}
end
