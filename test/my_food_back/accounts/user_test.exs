defmodule MyFoodBack.Accounts.UserTest do
  use MyFoodBack.DataCase, async: true

  alias MyFoodBack.Accounts.User
  alias MyFoodBack.Accounts.UserPreferences
  alias MyFoodBack.Accounts.UserSlotCookingTime

  describe "onboarding profile changeset" do
    test "accepts valid profile fields" do
      changeset =
        User.onboarding_profile_changeset(%User{}, %{
          display_name: "Lucca",
          household_size: 2,
          cooking_skill: "intermediate"
        })

      assert changeset.valid?
    end

    test "requires display_name" do
      changeset =
        User.onboarding_profile_changeset(%User{}, %{
          household_size: 1,
          cooking_skill: "beginner"
        })

      refute changeset.valid?
      assert %{display_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects whitespace-only display_name" do
      changeset =
        User.onboarding_profile_changeset(%User{}, %{
          display_name: "   ",
          household_size: 1,
          cooking_skill: "beginner"
        })

      refute changeset.valid?
      assert %{display_name: ["can't be blank"]} = errors_on(changeset)
    end

    test "trims display_name before storing it" do
      changeset =
        User.onboarding_profile_changeset(%User{}, %{
          display_name: "  Lucca  ",
          household_size: 1,
          cooking_skill: "beginner"
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :display_name) == "Lucca"
    end

    test "rejects display_name longer than 60 characters" do
      changeset =
        User.onboarding_profile_changeset(%User{}, %{
          display_name: String.duplicate("a", 61),
          household_size: 1,
          cooking_skill: "beginner"
        })

      refute changeset.valid?
      assert %{display_name: [_]} = errors_on(changeset)
    end

    test "rejects household_size below 1" do
      changeset =
        User.onboarding_profile_changeset(%User{}, %{
          display_name: "Lucca",
          household_size: 0,
          cooking_skill: "beginner"
        })

      refute changeset.valid?
      assert %{household_size: [_]} = errors_on(changeset)
    end

    test "rejects household_size above 20" do
      changeset =
        User.onboarding_profile_changeset(%User{}, %{
          display_name: "Lucca",
          household_size: 21,
          cooking_skill: "beginner"
        })

      refute changeset.valid?
      assert %{household_size: [_]} = errors_on(changeset)
    end

    test "accepts only the three documented cooking_skill values" do
      for skill <- ["beginner", "intermediate", "advanced"] do
        changeset =
          User.onboarding_profile_changeset(%User{}, %{
            display_name: "Lucca",
            household_size: 1,
            cooking_skill: skill
          })

        assert changeset.valid?,
               "expected #{skill} to be valid, got: #{inspect(changeset.errors)}"
      end
    end

    test "rejects unknown cooking_skill value" do
      changeset =
        User.onboarding_profile_changeset(%User{}, %{
          display_name: "Lucca",
          household_size: 1,
          cooking_skill: "wizard"
        })

      refute changeset.valid?
      assert %{cooking_skill: [_]} = errors_on(changeset)
    end

    test "never clears onboarding_completed_at when editing profile" do
      completed_at = ~U[2026-06-08 12:00:00Z]
      user = %User{onboarding_completed_at: completed_at}

      changeset =
        User.onboarding_profile_changeset(user, %{
          display_name: "Lucca",
          household_size: 1,
          cooking_skill: "beginner"
        })

      applied = Ecto.Changeset.apply_changes(changeset)
      assert applied.onboarding_completed_at == completed_at
      refute Ecto.Changeset.get_change(changeset, :onboarding_completed_at)
    end
  end

  describe "user_preferences changeset" do
    test "accepts empty preferences" do
      changeset = UserPreferences.changeset(%UserPreferences{}, %{})
      assert changeset.valid?
    end

    test "accepts a valid diet code and arrays" do
      changeset =
        UserPreferences.changeset(%UserPreferences{}, %{
          diet: "omnivore",
          hard_restrictions: ["peanut"],
          soft_preferences: ["mushrooms"]
        })

      assert changeset.valid?
    end

    test "rejects unknown diet code" do
      changeset =
        UserPreferences.changeset(%UserPreferences{}, %{diet: "made-up-diet"})

      refute changeset.valid?
      assert %{diet: [_]} = errors_on(changeset)
    end

    test "rejects unknown hard_restriction code" do
      changeset =
        UserPreferences.changeset(%UserPreferences{}, %{
          hard_restrictions: ["not-a-real-restriction"]
        })

      refute changeset.valid?
      assert %{hard_restrictions: [_]} = errors_on(changeset)
    end

    test "accepts nil diet (user picks none yet)" do
      changeset =
        UserPreferences.changeset(%UserPreferences{}, %{
          diet: nil,
          hard_restrictions: [],
          soft_preferences: []
        })

      assert changeset.valid?
    end

    test "does not cast user_id from client attrs" do
      changeset =
        UserPreferences.changeset(%UserPreferences{user_id: "authenticated-user"}, %{
          user_id: "malicious-user",
          diet: "omnivore"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :user_id)
      assert Ecto.Changeset.apply_changes(changeset).user_id == "authenticated-user"
    end
  end

  describe "user_slot_cooking_time changeset" do
    test "accepts the three supported slots with default hunger level" do
      for slot <- ["breakfast", "lunch", "dinner"] do
        changeset =
          UserSlotCookingTime.changeset(%UserSlotCookingTime{}, %{
            meal_slot: slot,
            cooking_time_minutes: 0,
            hunger_level: "normal"
          })

        assert changeset.valid?, "expected #{slot} to be valid, got: #{inspect(changeset.errors)}"
      end
    end

    test "rejects unknown meal_slot" do
      changeset =
        UserSlotCookingTime.changeset(%UserSlotCookingTime{}, %{
          meal_slot: "snack",
          cooking_time_minutes: 15,
          hunger_level: "normal"
        })

      refute changeset.valid?
      assert %{meal_slot: [_]} = errors_on(changeset)
    end

    test "rejects negative cooking_time_minutes" do
      changeset =
        UserSlotCookingTime.changeset(%UserSlotCookingTime{}, %{
          meal_slot: "lunch",
          cooking_time_minutes: -1,
          hunger_level: "normal"
        })

      refute changeset.valid?
      assert %{cooking_time_minutes: [_]} = errors_on(changeset)
    end

    test "rejects unknown hunger_level" do
      changeset =
        UserSlotCookingTime.changeset(%UserSlotCookingTime{}, %{
          meal_slot: "dinner",
          cooking_time_minutes: 30,
          hunger_level: "huge"
        })

      refute changeset.valid?
      assert %{hunger_level: [_]} = errors_on(changeset)
    end

    test "requires meal_slot" do
      changeset =
        UserSlotCookingTime.changeset(%UserSlotCookingTime{}, %{
          cooking_time_minutes: 30,
          hunger_level: "strong"
        })

      refute changeset.valid?
      assert %{meal_slot: ["can't be blank"]} = errors_on(changeset)
    end

    test "does not cast user_id from client attrs" do
      changeset =
        UserSlotCookingTime.changeset(%UserSlotCookingTime{user_id: "authenticated-user"}, %{
          user_id: "malicious-user",
          meal_slot: "dinner",
          cooking_time_minutes: 30,
          hunger_level: "strong"
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :user_id)
      assert Ecto.Changeset.apply_changes(changeset).user_id == "authenticated-user"
    end
  end

  describe "schema persistence (migration contract)" do
    test "generic user changeset does not cast onboarding_completed_at" do
      now = ~U[2026-06-08 12:00:00Z]

      changeset =
        User.changeset(%User{}, %{
          email: "protected-completion@example.com",
          onboarding_completed_at: now
        })

      assert changeset.valid?
      refute Ecto.Changeset.get_change(changeset, :onboarding_completed_at)
    end

    test "users has household_size, cooking_skill, and onboarding_completed_at columns" do
      now = ~U[2026-06-08 12:00:00Z]

      assert {:ok, user} =
               %User{}
               |> User.changeset(%{email: "schema@example.com"})
               |> Repo.insert()

      assert {:ok, user} =
               user
               |> User.onboarding_profile_changeset(%{
                 display_name: "Schema",
                 household_size: 3,
                 cooking_skill: "advanced"
               })
               |> Repo.update()

      assert {:ok, user} =
               user
               |> User.completion_changeset(%{onboarding_completed_at: now})
               |> Repo.update()

      reloaded = Repo.get!(User, user.id)
      assert reloaded.household_size == 3
      assert reloaded.cooking_skill == "advanced"
      assert reloaded.onboarding_completed_at == now
    end

    test "user_preferences row persists one-per-user with all three fields" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "prefs@example.com"})
        |> Repo.insert()

      assert {:ok, prefs} =
               %UserPreferences{user_id: user.id}
               |> UserPreferences.changeset(%{
                 diet: "omnivore",
                 hard_restrictions: ["peanut"],
                 soft_preferences: ["mushrooms"]
               })
               |> Repo.insert()

      reloaded = Repo.get!(UserPreferences, prefs.id)
      assert reloaded.user_id == user.id
      assert reloaded.diet == "omnivore"
      assert reloaded.hard_restrictions == ["peanut"]
      assert reloaded.soft_preferences == ["mushrooms"]
    end

    test "user_preferences uniqueness on user_id" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "unique-prefs@example.com"})
        |> Repo.insert()

      {:ok, _first} =
        %UserPreferences{user_id: user.id}
        |> UserPreferences.changeset(%{})
        |> Repo.insert()

      result =
        %UserPreferences{user_id: user.id}
        |> UserPreferences.changeset(%{})
        |> Repo.insert()

      assert {:error, _changeset} = result
      assert Repo.aggregate(UserPreferences, :count) == 1
    end

    test "user_slot_cooking_times row persists per (user, meal_slot)" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "slots@example.com"})
        |> Repo.insert()

      assert {:ok, row} =
               %UserSlotCookingTime{user_id: user.id}
               |> UserSlotCookingTime.changeset(%{
                 meal_slot: "dinner",
                 cooking_time_minutes: 45,
                 hunger_level: "strong"
               })
               |> Repo.insert()

      reloaded = Repo.get!(UserSlotCookingTime, row.id)
      assert reloaded.user_id == user.id
      assert reloaded.meal_slot == "dinner"
      assert reloaded.cooking_time_minutes == 45
      assert reloaded.hunger_level == "strong"
    end

    test "user_slot_cooking_times uniqueness on (user_id, meal_slot)" do
      {:ok, user} =
        %User{}
        |> User.changeset(%{email: "slot-unique@example.com"})
        |> Repo.insert()

      {:ok, _first} =
        %UserSlotCookingTime{user_id: user.id}
        |> UserSlotCookingTime.changeset(%{
          meal_slot: "lunch",
          cooking_time_minutes: 20,
          hunger_level: "normal"
        })
        |> Repo.insert()

      result =
        %UserSlotCookingTime{user_id: user.id}
        |> UserSlotCookingTime.changeset(%{
          meal_slot: "lunch",
          cooking_time_minutes: 25,
          hunger_level: "light"
        })
        |> Repo.insert()

      assert {:error, _changeset} = result
      assert Repo.aggregate(UserSlotCookingTime, :count) == 1
    end
  end
end
