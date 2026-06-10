defmodule MyFoodBack.Accounts.OnboardingTest do
  use MyFoodBack.DataCase, async: false

  import Ecto.Query

  alias MyFoodBack.Accounts
  alias MyFoodBack.Accounts.{User, UserPreferences, UserSlotCookingTime}
  alias MyFoodBack.Repo

  @valid_profile %{
    "displayName" => "Lucca",
    "householdSize" => 1,
    "cookingSkill" => "beginner"
  }

  @valid_preferences %{
    "diet" => "omnivore",
    "hardRestrictions" => ["peanut"],
    "softPreferences" => ["mushrooms"]
  }

  @valid_slots %{
    "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "light"},
    "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
    "dinner" => %{"cookingTimeMinutes" => 45, "hungerLevel" => "strong"}
  }

  setup do
    {:ok, %{user: user, account: account}} =
      Accounts.create_individual_account(%{email: "onboarding@example.com"},
        now: ~U[2026-06-08 12:00:00Z]
      )

    %{user: user, account: account}
  end

  describe "complete_onboarding/3" do
    test "persists profile, preferences, three slot rows, and stamps completion atomically", %{
      user: user
    } do
      now = ~U[2026-06-08 12:00:00Z]

      assert {:ok, result} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: now
               )

      assert result.user.id == user.id
      assert result.user.display_name == "Lucca"
      assert result.user.household_size == 1
      assert result.user.cooking_skill == "beginner"
      assert result.user.onboarding_completed_at == now

      assert result.preferences.diet == "omnivore"
      assert result.preferences.hard_restrictions == ["peanut"]
      assert result.preferences.soft_preferences == ["mushrooms"]

      assert length(result.slot_cooking_times) == 3

      for slot <- ["breakfast", "lunch", "dinner"] do
        assert Enum.any?(result.slot_cooking_times, &(&1.meal_slot == slot))
      end
    end

    test "is rejected when onboarding is already complete (one-way guard)", %{user: user} do
      first_now = ~U[2026-06-08 12:00:00Z]

      assert {:ok, _} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: first_now
               )

      assert {:error, %{code: "onboarding_already_complete"}} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => %{
                     "displayName" => "Other",
                     "householdSize" => 5,
                     "cookingSkill" => "advanced"
                   },
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: DateTime.add(first_now, 60, :second)
               )
    end

    test "does NOT stamp completion if any group is invalid (atomic rollback)", %{user: user} do
      invalid_slots = Map.delete(@valid_slots, "dinner")

      assert {:error, %{code: "onboarding_invalid"}} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => invalid_slots
                 },
                 now: ~U[2026-06-08 12:00:00Z]
               )

      reloaded = Repo.get!(User, user.id)
      assert is_nil(reloaded.display_name)
      assert is_nil(reloaded.onboarding_completed_at)

      assert Repo.all(UserPreferences) == []
      assert Repo.all(UserSlotCookingTime) == []
    end

    test "does NOT stamp completion if profile is invalid", %{user: user} do
      bad_profile = Map.put(@valid_profile, "cookingSkill", "wizard")

      assert {:error, %{code: "onboarding_invalid"}} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => bad_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: ~U[2026-06-08 12:00:00Z]
               )

      reloaded = Repo.get!(User, user.id)
      assert is_nil(reloaded.onboarding_completed_at)
      assert Repo.all(UserPreferences) == []
      assert Repo.all(UserSlotCookingTime) == []
    end

    test "does NOT stamp completion if preferences are invalid", %{user: user} do
      bad_prefs = Map.put(@valid_preferences, "diet", "made-up-diet")

      assert {:error, %{code: "onboarding_invalid"}} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => bad_prefs,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: ~U[2026-06-08 12:00:00Z]
               )

      reloaded = Repo.get!(User, user.id)
      assert is_nil(reloaded.onboarding_completed_at)
      assert Repo.all(UserPreferences) == []
      assert Repo.all(UserSlotCookingTime) == []
    end

    test "ignores malicious userId/user_id in nested preferences and slot payloads", %{user: user} do
      {:ok, %{user: other}} =
        Accounts.create_individual_account(%{email: "payload-owner@example.com"},
          now: ~U[2026-06-08 12:00:00Z]
        )

      malicious_preferences =
        @valid_preferences
        |> Map.put("userId", other.id)
        |> Map.put("user_id", other.id)

      malicious_slots =
        for {slot, attrs} <- @valid_slots, into: %{} do
          {slot, attrs |> Map.put("userId", other.id) |> Map.put("user_id", other.id)}
        end

      assert {:ok, result} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => malicious_preferences,
                   "slotCookingTimes" => malicious_slots
                 },
                 now: ~U[2026-06-08 12:00:00Z]
               )

      assert result.preferences.user_id == user.id
      assert Enum.all?(result.slot_cooking_times, &(&1.user_id == user.id))
      assert Repo.get_by(UserPreferences, user_id: other.id) == nil
      assert Repo.all(from row in UserSlotCookingTime, where: row.user_id == ^other.id) == []
    end

    test "updates existing preferences and slot rows instead of inserting duplicates", %{
      user: user
    } do
      {:ok, _existing_preferences} =
        Accounts.update_user_preferences(user, %{
          "diet" => "vegetarian",
          "hardRestrictions" => ["gluten"],
          "softPreferences" => ["beans"]
        })

      {:ok, _existing_slots} =
        Accounts.update_slot_cooking_times(user, %{
          "breakfast" => %{"cookingTimeMinutes" => 5, "hungerLevel" => "light"},
          "lunch" => %{"cookingTimeMinutes" => 15, "hungerLevel" => "normal"},
          "dinner" => %{"cookingTimeMinutes" => 25, "hungerLevel" => "strong"}
        })

      now = ~U[2026-06-08 12:00:00Z]

      assert {:ok, result} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: now
               )

      assert result.user.onboarding_completed_at == now
      assert result.preferences.diet == "omnivore"
      assert result.preferences.hard_restrictions == ["peanut"]
      assert result.preferences.soft_preferences == ["mushrooms"]

      assert Repo.aggregate(UserPreferences, :count) == 1
      assert Repo.aggregate(UserSlotCookingTime, :count) == 3

      assert {:ok, slots} = Accounts.get_slot_cooking_times(user)
      assert slots == @valid_slots
    end

    test "is idempotent on the same submission: already complete wins over second call", %{
      user: user
    } do
      now = ~U[2026-06-08 12:00:00Z]

      assert {:ok, _} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: now
               )

      reloaded = Repo.get!(User, user.id)

      assert {:error, %{code: "onboarding_already_complete"}} =
               Accounts.complete_onboarding(
                 reloaded,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: now
               )
    end

    test "already complete wins even when retry payload would otherwise be invalid", %{user: user} do
      now = ~U[2026-06-08 12:00:00Z]

      assert {:ok, _} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: now
               )

      invalid_retry_payload = %{
        "profile" => Map.put(@valid_profile, "displayName", "   "),
        "preferences" => Map.put(@valid_preferences, "diet", "made-up-diet"),
        "slotCookingTimes" => Map.delete(@valid_slots, "dinner")
      }

      assert {:error, %{code: "onboarding_already_complete"}} =
               Accounts.complete_onboarding(user, invalid_retry_payload,
                 now: DateTime.add(now, 1, :second)
               )
    end

    test "rejects whitespace-only display name without stamping completion", %{user: user} do
      payload = %{
        "profile" => Map.put(@valid_profile, "displayName", "   "),
        "preferences" => @valid_preferences,
        "slotCookingTimes" => @valid_slots
      }

      assert {:error, %{code: "onboarding_invalid"}} =
               Accounts.complete_onboarding(user, payload, now: ~U[2026-06-08 12:00:00Z])

      reloaded = Repo.get!(User, user.id)
      assert is_nil(reloaded.onboarding_completed_at)
    end
  end

  describe "user preferences read/update" do
    test "get_user_preferences/1 returns nil when no row exists", %{user: user} do
      assert {:ok, nil} = Accounts.get_user_preferences(user)
    end

    test "get_user_preferences/1 returns the saved row scoped to the user", %{user: user} do
      {:ok, %{user: other}} =
        Accounts.create_individual_account(%{email: "other@example.com"},
          now: ~U[2026-06-08 12:00:00Z]
        )

      {:ok, _mine} =
        %UserPreferences{user_id: user.id}
        |> UserPreferences.changeset(%{diet: "omnivore"})
        |> Repo.insert()

      {:ok, _theirs} =
        %UserPreferences{user_id: other.id}
        |> UserPreferences.changeset(%{diet: "vegetarian"})
        |> Repo.insert()

      assert {:ok, prefs} = Accounts.get_user_preferences(user)
      assert prefs.diet == "omnivore"
    end

    test "update_user_preferences/2 upserts a row and returns the new shape", %{user: user} do
      attrs = %{"diet" => "omnivore", "hardRestrictions" => [], "softPreferences" => []}

      assert {:ok, prefs} = Accounts.update_user_preferences(user, attrs)
      assert prefs.diet == "omnivore"
      assert prefs.user_id == user.id

      assert {:ok, prefs} =
               Accounts.update_user_preferences(user, %{
                 "diet" => "pescatarian",
                 "hardRestrictions" => ["shellfish"],
                 "softPreferences" => ["cilantro"]
               })

      assert prefs.diet == "pescatarian"
      assert prefs.hard_restrictions == ["shellfish"]
      assert prefs.soft_preferences == ["cilantro"]
      assert Repo.aggregate(UserPreferences, :count) == 1
    end

    test "update_user_preferences/2 returns preferences_invalid for unknown catalog code", %{
      user: user
    } do
      assert {:error, %{code: "preferences_invalid"}} =
               Accounts.update_user_preferences(user, %{"diet" => "made-up-diet"})
    end

    test "update_user_preferences/2 never modifies onboarding_completed_at", %{user: user} do
      now = ~U[2026-06-08 12:00:00Z]

      assert {:ok, _} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: now
               )

      assert {:ok, _} =
               Accounts.update_user_preferences(user, %{
                 "diet" => nil,
                 "hardRestrictions" => [],
                 "softPreferences" => []
               })

      reloaded = Repo.get!(User, user.id)
      assert reloaded.onboarding_completed_at == now
    end

    test "update_user_preferences/2 ignores malicious userId/user_id payload keys", %{user: user} do
      {:ok, %{user: other}} =
        Accounts.create_individual_account(%{email: "malicious-prefs-other@example.com"},
          now: ~U[2026-06-08 12:00:00Z]
        )

      assert {:ok, prefs} =
               Accounts.update_user_preferences(user, %{
                 "userId" => other.id,
                 "user_id" => other.id,
                 "diet" => "omnivore",
                 "hardRestrictions" => [],
                 "softPreferences" => []
               })

      assert prefs.user_id == user.id
      assert Repo.get_by(UserPreferences, user_id: other.id) == nil
    end

    test "update_user_preferences/2 is safe for concurrent first saves", %{user: user} do
      first_attrs = %{
        "diet" => "omnivore",
        "hardRestrictions" => [],
        "softPreferences" => ["mushrooms"]
      }

      second_attrs = %{
        "diet" => "vegetarian",
        "hardRestrictions" => ["gluten"],
        "softPreferences" => ["beans"]
      }

      tasks =
        for attrs <- [first_attrs, second_attrs] do
          Task.async(fn -> Accounts.update_user_preferences(user, attrs) end)
        end

      results = Enum.map(tasks, &Task.await(&1, 5_000))

      assert Enum.all?(
               results,
               &match?({:ok, %UserPreferences{user_id: user_id}} when user_id == user.id, &1)
             )

      assert Repo.aggregate(UserPreferences, :count) == 1

      assert {:ok, final_preferences} = Accounts.get_user_preferences(user)
      assert final_preferences.user_id == user.id
      assert final_preferences.diet in ["omnivore", "vegetarian"]
    end
  end

  describe "slot cooking times read/update" do
    test "get_slot_cooking_times/1 returns defaults when no rows exist", %{user: user} do
      assert {:ok, defaults} = Accounts.get_slot_cooking_times(user)

      assert defaults == %{
               "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "lunch" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "dinner" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"}
             }
    end

    test "get_slot_cooking_times/1 merges saved rows with defaults", %{user: user} do
      {:ok, _} =
        %UserSlotCookingTime{user_id: user.id}
        |> UserSlotCookingTime.changeset(%{
          meal_slot: "breakfast",
          cooking_time_minutes: 10,
          hunger_level: "light"
        })
        |> Repo.insert()

      assert {:ok,
              %{
                "breakfast" => %{"cookingTimeMinutes" => 10, "hungerLevel" => "light"},
                "lunch" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
                "dinner" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"}
              }} = Accounts.get_slot_cooking_times(user)
    end

    test "get_slot_cooking_times/1 is scoped to the user (cross-user isolation)", %{user: user} do
      {:ok, %{user: other}} =
        Accounts.create_individual_account(%{email: "slot-other@example.com"},
          now: ~U[2026-06-08 12:00:00Z]
        )

      {:ok, _} =
        %UserSlotCookingTime{user_id: other.id}
        |> UserSlotCookingTime.changeset(%{
          meal_slot: "dinner",
          cooking_time_minutes: 60,
          hunger_level: "strong"
        })
        |> Repo.insert()

      assert {:ok, defaults} = Accounts.get_slot_cooking_times(user)
      assert defaults["dinner"] == %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"}
    end

    test "update_slot_cooking_times/2 upserts the three slots and returns the canonical shape", %{
      user: user
    } do
      attrs = %{
        "breakfast" => %{"cookingTimeMinutes" => 10, "hungerLevel" => "light"},
        "lunch" => %{"cookingTimeMinutes" => 20, "hungerLevel" => "normal"},
        "dinner" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "strong"}
      }

      assert {:ok, result} = Accounts.update_slot_cooking_times(user, attrs)
      assert result == attrs
      assert Repo.aggregate(UserSlotCookingTime, :count) == 3

      assert {:ok, ^attrs} = Accounts.update_slot_cooking_times(user, attrs)
      assert Repo.aggregate(UserSlotCookingTime, :count) == 3
    end

    test "update_slot_cooking_times/2 rejects unknown slot with slot_cooking_times_invalid", %{
      user: user
    } do
      attrs = %{
        "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "light"},
        "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
        "dinner" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
        "snack" => %{"cookingTimeMinutes" => 10, "hungerLevel" => "light"}
      }

      assert {:error, %{code: "slot_cooking_times_invalid"}} =
               Accounts.update_slot_cooking_times(user, attrs)
    end

    test "update_slot_cooking_times/2 rejects unknown hunger_level", %{user: user} do
      attrs = %{
        "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "light"},
        "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "huge"},
        "dinner" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"}
      }

      assert {:error, %{code: "slot_cooking_times_invalid"}} =
               Accounts.update_slot_cooking_times(user, attrs)
    end

    test "update_slot_cooking_times/2 rejects negative minutes", %{user: user} do
      attrs = %{
        "breakfast" => %{"cookingTimeMinutes" => -1, "hungerLevel" => "light"},
        "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
        "dinner" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"}
      }

      assert {:error, %{code: "slot_cooking_times_invalid"}} =
               Accounts.update_slot_cooking_times(user, attrs)
    end

    test "update_slot_cooking_times/2 never modifies onboarding_completed_at", %{user: user} do
      now = ~U[2026-06-08 12:00:00Z]

      assert {:ok, _} =
               Accounts.complete_onboarding(
                 user,
                 %{
                   "profile" => @valid_profile,
                   "preferences" => @valid_preferences,
                   "slotCookingTimes" => @valid_slots
                 },
                 now: now
               )

      assert {:ok, _} =
               Accounts.update_slot_cooking_times(user, %{
                 "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
                 "lunch" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
                 "dinner" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"}
               })

      reloaded = Repo.get!(User, user.id)
      assert reloaded.onboarding_completed_at == now
    end

    test "update_slot_cooking_times/2 ignores malicious userId/user_id nested payload keys", %{
      user: user
    } do
      {:ok, %{user: other}} =
        Accounts.create_individual_account(%{email: "malicious-slots-other@example.com"},
          now: ~U[2026-06-08 12:00:00Z]
        )

      attrs =
        for {slot, slot_attrs} <- @valid_slots, into: %{} do
          {slot, slot_attrs |> Map.put("userId", other.id) |> Map.put("user_id", other.id)}
        end

      assert {:ok, _} = Accounts.update_slot_cooking_times(user, attrs)

      assert Repo.aggregate(
               from(row in UserSlotCookingTime, where: row.user_id == ^user.id),
               :count
             ) == 3

      assert Repo.all(from row in UserSlotCookingTime, where: row.user_id == ^other.id) == []
    end
  end
end
