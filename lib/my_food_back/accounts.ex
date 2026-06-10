defmodule MyFoodBack.Accounts do
  import Ecto.Query

  alias Ecto.Multi
  alias MyFoodBack.Accounts.{Account, Membership, User, UserPreferences, UserSlotCookingTime}
  alias MyFoodBack.Repo

  @trial_days 10
  @supported_slots ~w(breakfast lunch dinner)
  @slot_atom_keys %{"breakfast" => :breakfast, "lunch" => :lunch, "dinner" => :dinner}
  @slot_defaults %{"breakfast" => 0, "lunch" => 0, "dinner" => 0}
  @hunger_defaults %{"breakfast" => "normal", "lunch" => "normal", "dinner" => "normal"}
  @profile_keys %{
    "displayName" => :display_name,
    "display_name" => :display_name,
    :display_name => :display_name,
    "householdSize" => :household_size,
    "household_size" => :household_size,
    :household_size => :household_size,
    "cookingSkill" => :cooking_skill,
    "cooking_skill" => :cooking_skill,
    :cooking_skill => :cooking_skill
  }
  @preferences_keys %{
    "diet" => :diet,
    :diet => :diet,
    "hardRestrictions" => :hard_restrictions,
    "hard_restrictions" => :hard_restrictions,
    :hard_restrictions => :hard_restrictions,
    "softPreferences" => :soft_preferences,
    "soft_preferences" => :soft_preferences,
    :soft_preferences => :soft_preferences
  }
  @slot_value_keys %{
    "mealSlot" => :meal_slot,
    "meal_slot" => :meal_slot,
    :meal_slot => :meal_slot,
    "cookingTimeMinutes" => :cooking_time_minutes,
    "cooking_time_minutes" => :cooking_time_minutes,
    :cooking_time_minutes => :cooking_time_minutes,
    "hungerLevel" => :hunger_level,
    "hunger_level" => :hunger_level,
    :hunger_level => :hunger_level
  }

  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  def normalize_email(other), do: other

  def create_individual_account(attrs, opts \\ []) do
    attrs
    |> create_individual_account_multi(opts)
    |> Repo.transaction()
  end

  def create_individual_account_multi(attrs, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    trial_ends_at = DateTime.add(now, @trial_days, :day)

    Multi.new()
    |> Multi.insert(:user, User.changeset(%User{}, attrs))
    |> Multi.insert(:account, fn _changes ->
      Account.changeset(%Account{}, %{
        type: "individual",
        trial_started_at: now,
        trial_ends_at: trial_ends_at,
        subscription_status: "none"
      })
    end)
    |> Multi.insert(:membership, fn %{user: user, account: account} ->
      %Membership{user_id: user.id, account_id: account.id}
      |> Membership.changeset(%{role: "owner", status: "active"})
    end)
  end

  def get_current_account(%User{id: user_id}), do: get_current_account(user_id)

  def get_current_account(user_id) when is_binary(user_id) do
    query =
      from(membership in Membership,
        where: membership.user_id == ^user_id and membership.status == "active",
        join: account in assoc(membership, :account),
        where: account.type == "individual",
        preload: [account: account],
        order_by: [desc: membership.inserted_at, desc: membership.id],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      membership -> {:ok, %{membership: membership, account: membership.account}}
    end
  end

  def access_state(%Account{subscription_status: "active"}, _now) do
    %{can_use_app: true, reason: nil}
  end

  def access_state(%Account{trial_ends_at: trial_ends_at}, now) do
    if DateTime.compare(now, trial_ends_at) == :lt do
      %{can_use_app: true, reason: nil}
    else
      %{can_use_app: false, reason: "trial_expired"}
    end
  end

  def complete_onboarding(%User{id: user_id}, attrs, opts \\ []) do
    fresh = Repo.get!(User, user_id)

    if fresh.onboarding_completed_at do
      error(:onboarding_already_complete)
    else
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

      with {:ok, profile_changeset} <- build_profile_changeset(fresh, attrs),
           {:ok, preferences_changeset} <- build_preferences_changeset(fresh, attrs),
           {:ok, slot_changesets} <- build_slot_changesets(fresh, attrs) do
        multi =
          Multi.new()
          |> Multi.update(:user, profile_changeset)
          |> Multi.insert(:preferences, preferences_changeset)
          |> Multi.merge(fn _ -> insert_slots_multi(slot_changesets) end)
          |> Multi.update(:complete_user, fn %{user: user} ->
            User.completion_changeset(user, %{onboarding_completed_at: now})
          end)

        case Repo.transaction(multi) do
          {:ok,
           %{
             user: _profile_user,
             complete_user: user,
             preferences: preferences,
             slot_cooking_times: rows
           }} ->
            {:ok,
             %{
               user: user,
               preferences: preferences,
               slot_cooking_times: rows
             }}

          {:error, _step, %{errors: errors} = changeset, _changes} ->
            onboarding_invalid(error: errors, changeset: changeset)

          {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
            onboarding_invalid(error: changeset_errors(changeset), changeset: changeset)

          {:error, _step, reason, _changes} when is_atom(reason) ->
            {:error, %{code: Atom.to_string(reason)}}

          {:error, _step, reason, _changes} ->
            {:error, %{code: "onboarding_invalid", reason: reason}}
        end
      end
    end
  end

  defp build_profile_changeset(user, attrs) do
    profile = nested_attrs(attrs, ["profile", :profile], %{})

    changeset =
      user
      |> User.onboarding_profile_changeset(whitelisted_attrs(profile, @profile_keys))

    if changeset.valid? do
      {:ok, changeset}
    else
      onboarding_invalid(error: changeset_errors(changeset), changeset: changeset)
    end
  end

  defp build_preferences_changeset(user, attrs) do
    preferences = nested_attrs(attrs, ["preferences", :preferences], %{})

    changeset =
      %UserPreferences{user_id: user.id}
      |> UserPreferences.changeset(whitelisted_attrs(preferences, @preferences_keys))

    if changeset.valid? do
      {:ok, changeset}
    else
      onboarding_invalid(error: changeset_errors(changeset), changeset: changeset)
    end
  end

  defp build_slot_changesets(user, attrs) do
    slots = nested_attrs(attrs, ["slotCookingTimes", :slot_cooking_times], %{})

    cond do
      not is_map(slots) or map_size(slots) != 3 ->
        {:error, %{code: "onboarding_invalid", error: "slot cooking times must include 3 slots"}}

      true ->
        slot_changesets =
          for slot <- @supported_slots, into: %{} do
            value = slot_value(slots, slot)

            normalized =
              value
              |> whitelisted_attrs(@slot_value_keys)
              |> Map.put(:meal_slot, slot)

            changeset =
              %UserSlotCookingTime{user_id: user.id}
              |> UserSlotCookingTime.changeset(normalized)

            {slot, changeset}
          end

        if Enum.all?(slot_changesets, fn {_slot, cs} -> cs.valid? end) do
          {:ok, slot_changesets}
        else
          {_slot, bad} = Enum.find(slot_changesets, fn {_slot, cs} -> not cs.valid? end)
          onboarding_invalid(error: changeset_errors(bad), changeset: bad)
        end
    end
  end

  defp insert_slots_multi(changesets) do
    multi =
      Enum.reduce(changesets, Multi.new(), fn {slot, changeset}, multi ->
        Multi.insert(multi, {:slot, slot}, changeset)
      end)

    Multi.run(multi, :slot_cooking_times, fn _repo, changes ->
      rows =
        for slot <- @supported_slots do
          Map.fetch!(changes, {:slot, slot})
        end

      {:ok, rows}
    end)
  end

  defp nested_attrs(attrs, keys, default) do
    Enum.find_value(keys, default, fn key ->
      case Map.get(attrs, key) do
        nil -> false
        value -> value
      end
    end)
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end

  defp onboarding_invalid(fields) do
    {:error, Map.merge(%{code: "onboarding_invalid"}, Map.new(fields))}
  end

  def get_user_preferences(%User{id: user_id}) do
    case Repo.get_by(UserPreferences, user_id: user_id) do
      nil -> {:ok, nil}
      %UserPreferences{} = prefs -> {:ok, prefs}
    end
  end

  def update_user_preferences(%User{id: user_id}, attrs) do
    case Repo.get_by(UserPreferences, user_id: user_id) do
      nil ->
        %UserPreferences{user_id: user_id}
        |> UserPreferences.changeset(whitelisted_attrs(attrs, @preferences_keys))
        |> Repo.insert()
        |> case do
          {:ok, prefs} -> {:ok, prefs}
          {:error, changeset} -> {:error, %{code: "preferences_invalid", changeset: changeset}}
        end

      %UserPreferences{} = existing ->
        existing
        |> UserPreferences.changeset(whitelisted_attrs(attrs, @preferences_keys))
        |> Repo.update()
        |> case do
          {:ok, prefs} -> {:ok, prefs}
          {:error, changeset} -> {:error, %{code: "preferences_invalid", changeset: changeset}}
        end
    end
  end

  defp whitelisted_attrs(attrs, allowed_keys) when is_map(attrs) do
    Enum.reduce(attrs, %{}, fn {key, value}, acc ->
      case Map.fetch(allowed_keys, key) do
        {:ok, normalized_key} -> Map.put(acc, normalized_key, value)
        :error -> acc
      end
    end)
  end

  defp whitelisted_attrs(_attrs, _allowed_keys), do: %{}

  defp slot_value(slots, slot) do
    Map.get(slots, slot) || Map.get(slots, Map.fetch!(@slot_atom_keys, slot))
  end

  def get_slot_cooking_times(%User{id: user_id}) do
    query =
      from(row in UserSlotCookingTime, where: row.user_id == ^user_id)

    rows = Repo.all(query)

    defaults =
      for slot <- @supported_slots, into: %{} do
        {slot,
         %{
           "cookingTimeMinutes" => Map.get(@slot_defaults, slot),
           "hungerLevel" => Map.get(@hunger_defaults, slot)
         }}
      end

    merged =
      for row <- rows, into: defaults do
        {row.meal_slot,
         %{"cookingTimeMinutes" => row.cooking_time_minutes, "hungerLevel" => row.hunger_level}}
      end

    {:ok, merged}
  end

  def update_slot_cooking_times(%User{id: user_id}, attrs) when is_map(attrs) do
    normalized =
      for {slot, value} <- attrs, into: %{} do
        {to_string(slot), value}
      end

    cond do
      map_size(normalized) != 3 ->
        {:error, %{code: "slot_cooking_times_invalid", reason: "expected 3 slots"}}

      not Enum.all?(@supported_slots, &Map.has_key?(normalized, &1)) ->
        {:error, %{code: "slot_cooking_times_invalid", reason: "missing required slot"}}

      Enum.any?(normalized, fn {_slot, value} ->
        not (is_map(value) and Map.has_key?(value, "cookingTimeMinutes") and
                 Map.has_key?(value, "hungerLevel"))
      end) ->
        {:error, %{code: "slot_cooking_times_invalid", reason: "missing required field"}}

      true ->
        upsert_slot_cooking_times(user_id, normalized)
    end
  end

  defp upsert_slot_cooking_times(user_id, normalized) do
    multi =
      Enum.reduce(@supported_slots, Multi.new(), fn slot, multi ->
        value = Map.fetch!(normalized, slot)

        attrs = %{
          user_id: user_id,
          meal_slot: slot,
          cooking_time_minutes: value["cookingTimeMinutes"],
          hunger_level: value["hungerLevel"]
        }

        changeset = UserSlotCookingTime.changeset(%UserSlotCookingTime{user_id: user_id}, attrs)

        Multi.insert(multi, {:slot, slot}, changeset,
          on_conflict: {:replace, [:cooking_time_minutes, :hunger_level, :updated_at]},
          conflict_target: [:user_id, :meal_slot]
        )
      end)

    case Repo.transaction(multi) do
      {:ok, changes} ->
        rows =
          for slot <- @supported_slots, into: %{} do
            row = Map.fetch!(changes, {:slot, slot})

            {slot,
             %{
               "cookingTimeMinutes" => row.cooking_time_minutes,
               "hungerLevel" => row.hunger_level
             }}
          end

        {:ok, rows}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, %{code: "slot_cooking_times_invalid", changeset: changeset}}

      {:error, _step, reason, _changes} when is_atom(reason) ->
        {:error, %{code: "slot_cooking_times_invalid", reason: Atom.to_string(reason)}}

      {:error, _step, reason, _changes} ->
        {:error, %{code: "slot_cooking_times_invalid", reason: reason}}
    end
  end

  defp error(code), do: {:error, %{code: Atom.to_string(code)}}
end
