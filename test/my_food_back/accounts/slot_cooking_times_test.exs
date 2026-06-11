defmodule MyFoodBack.Accounts.SlotCookingTimesTest do
  use MyFoodBack.DataCase, async: true

  alias MyFoodBack.Accounts.SlotCookingTimes

  describe "supported_slots/0" do
    test "returns the three canonical slot names in order" do
      assert SlotCookingTimes.supported_slots() == ~w(breakfast lunch dinner)
    end
  end

  describe "hunger_levels/0" do
    test "returns the three hunger level codes" do
      assert SlotCookingTimes.hunger_levels() == ~w(light normal strong)
    end
  end

  describe "supported_slot?/1" do
    test "accepts the supported slot strings" do
      for slot <- ~w(breakfast lunch dinner) do
        assert SlotCookingTimes.supported_slot?(slot)
      end
    end

    test "accepts the supported slot atoms" do
      for slot <- [:breakfast, :lunch, :dinner] do
        assert SlotCookingTimes.supported_slot?(slot)
      end
    end

    test "rejects unknown slots" do
      refute SlotCookingTimes.supported_slot?("snack")
      refute SlotCookingTimes.supported_slot?(:snack)
      refute SlotCookingTimes.supported_slot?(nil)
    end
  end

  describe "defaults/0" do
    test "returns the three-slot canonical shape with 0 minutes and normal hunger" do
      assert SlotCookingTimes.defaults() == %{
               "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "lunch" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "dinner" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"}
             }
    end
  end

  describe "canonical_value/1" do
    test "produces the camelCase JSON shape for a saved row" do
      assert SlotCookingTimes.canonical_value(%{
               cooking_time_minutes: 30,
               hunger_level: "strong"
             }) == %{"cookingTimeMinutes" => 30, "hungerLevel" => "strong"}
    end
  end

  describe "merge_with_defaults/1" do
    test "returns defaults when no rows are passed" do
      assert SlotCookingTimes.merge_with_defaults([]) == SlotCookingTimes.defaults()
    end

    test "overlays a saved row on top of the defaults" do
      row = %{meal_slot: "breakfast", cooking_time_minutes: 10, hunger_level: "light"}

      assert SlotCookingTimes.merge_with_defaults([row]) == %{
               "breakfast" => %{"cookingTimeMinutes" => 10, "hungerLevel" => "light"},
               "lunch" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "dinner" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"}
             }
    end

    test "later rows for the same slot win over earlier ones" do
      rows = [
        %{meal_slot: "dinner", cooking_time_minutes: 10, hunger_level: "light"},
        %{meal_slot: "dinner", cooking_time_minutes: 60, hunger_level: "strong"}
      ]

      merged = SlotCookingTimes.merge_with_defaults(rows)
      assert merged["dinner"] == %{"cookingTimeMinutes" => 60, "hungerLevel" => "strong"}
    end
  end

  describe "stringify_keys/1" do
    test "coerces atom top-level keys to strings" do
      assert SlotCookingTimes.stringify_keys(%{breakfast: 1, dinner: 3}) ==
               %{"breakfast" => 1, "dinner" => 3}
    end

    test "leaves string keys untouched" do
      assert SlotCookingTimes.stringify_keys(%{"lunch" => 2}) == %{"lunch" => 2}
    end
  end

  describe "fetch_slot/2" do
    test "looks up a slot by its string key" do
      slots = %{"breakfast" => :a, "lunch" => :b, "dinner" => :c}
      assert SlotCookingTimes.fetch_slot(slots, "lunch") == :b
    end

    test "looks up a slot by its atom key" do
      slots = %{breakfast: :a, lunch: :b, dinner: :c}
      assert SlotCookingTimes.fetch_slot(slots, "lunch") == :b
    end

    test "returns nil for a missing slot" do
      assert SlotCookingTimes.fetch_slot(%{"breakfast" => 1}, "lunch") == nil
    end
  end

  describe "value_keys/0" do
    test "whitelists camelCase, snake_case, and atom keys for the three value fields" do
      keys = SlotCookingTimes.value_keys()

      assert keys["cookingTimeMinutes"] == :cooking_time_minutes
      assert keys["cooking_time_minutes"] == :cooking_time_minutes
      assert keys[:cooking_time_minutes] == :cooking_time_minutes

      assert keys["hungerLevel"] == :hunger_level
      assert keys["hunger_level"] == :hunger_level
      assert keys[:hunger_level] == :hunger_level

      assert keys["mealSlot"] == :meal_slot
      assert keys["meal_slot"] == :meal_slot
      assert keys[:meal_slot] == :meal_slot
    end
  end

  describe "validate_payload/1" do
    test "accepts a complete three-slot payload with the required value fields" do
      payload = %{
        "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
        "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
        "dinner" => %{"cookingTimeMinutes" => 45, "hungerLevel" => "normal"}
      }

      assert SlotCookingTimes.validate_payload(payload) == :ok
    end

    test "rejects payloads with a wrong number of slots" do
      payload = %{
        "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
        "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"}
      }

      assert SlotCookingTimes.validate_payload(payload) ==
               {:error, "slot_cooking_times_invalid", "expected 3 slots"}
    end

    test "rejects payloads that are missing a required slot" do
      payload = %{
        "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
        "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
        "snack" => %{"cookingTimeMinutes" => 10, "hungerLevel" => "normal"}
      }

      assert SlotCookingTimes.validate_payload(payload) ==
               {:error, "slot_cooking_times_invalid", "missing required slot"}
    end

    test "rejects slot values that are missing a required field" do
      payload = %{
        "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
        "lunch" => %{"hungerLevel" => "normal"},
        "dinner" => %{"cookingTimeMinutes" => 45, "hungerLevel" => "normal"}
      }

      assert SlotCookingTimes.validate_payload(payload) ==
               {:error, "slot_cooking_times_invalid", "missing required field"}
    end
  end
end
