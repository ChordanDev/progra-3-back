defmodule MyFoodBackWeb.OnboardingJSON do
  alias MyFoodBackWeb.AuthJSON
  alias MyFoodBackWeb.ErrorRendering

  def complete(%{result: %{user: user, preferences: prefs, slot_cooking_times: rows}}) do
    %{
      user: serialize_user(user),
      preferences: serialize_preferences(prefs),
      slotCookingTimes: serialize_slots(rows)
    }
  end

  def error(%{error: error}), do: %{error: AuthJSON.camelize(ErrorRendering.safe_error(error))}

  defp serialize_user(user) do
    %{
      id: user.id,
      displayName: user.display_name,
      householdSize: user.household_size,
      cookingSkill: user.cooking_skill,
      onboardingCompletedAt: format_dt(user.onboarding_completed_at)
    }
  end

  defp serialize_preferences(prefs) do
    %{
      diet: prefs.diet,
      hardRestrictions: prefs.hard_restrictions || [],
      softPreferences: prefs.soft_preferences || []
    }
  end

  defp serialize_slots(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      Map.put(acc, row.meal_slot, %{
        cookingTimeMinutes: row.cooking_time_minutes,
        hungerLevel: row.hunger_level
      })
    end)
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
