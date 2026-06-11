defmodule MyFoodBackWeb.OnboardingControllerTest do
  use MyFoodBackWeb.ConnCase, async: true

  import Ecto.Query

  alias MyFoodBack.Accounts.{UserPreferences, UserSlotCookingTime}
  alias MyFoodBack.Repo

  @valid_payload %{
    "profile" => %{
      "displayName" => "Lucca",
      "householdSize" => 1,
      "cookingSkill" => "beginner"
    },
    "preferences" => %{
      "diet" => "omnivore",
      "hardRestrictions" => ["peanut"],
      "softPreferences" => ["mushrooms"]
    },
    "slotCookingTimes" => %{
      "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "light"},
      "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
      "dinner" => %{"cookingTimeMinutes" => 45, "hungerLevel" => "strong"}
    }
  }

  describe "POST /api/onboarding/complete" do
    test "rejects anonymous requests with 401", %{conn: conn} do
      conn = post(conn, ~p"/api/onboarding/complete", @valid_payload)
      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end

    test "accepts a complete payload from an authenticated user, returns the saved shape", %{
      conn: conn
    } do
      auth = signup_user("onboard-controller@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{
               "user" => %{
                 "displayName" => "Lucca",
                 "householdSize" => 1,
                 "cookingSkill" => "beginner"
               },
               "preferences" => %{
                 "diet" => "omnivore",
                 "hardRestrictions" => ["peanut"],
                 "softPreferences" => ["mushrooms"]
               },
               "slotCookingTimes" => %{
                 "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "light"},
                 "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
                 "dinner" => %{"cookingTimeMinutes" => 45, "hungerLevel" => "strong"}
               }
             } = json_response(conn, 200)
    end

    test "locked account can still complete onboarding (setup endpoints are exempt from lock)", %{
      conn: conn
    } do
      auth = signup_user("locked-onboard@example.com")
      lock_current_account(auth)

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{
               "user" => %{"displayName" => "Lucca"}
             } = json_response(conn, 200)
    end

    test "rejects a second submission with onboarding_already_complete (idempotency)", %{
      conn: conn
    } do
      auth = signup_user("dup-onboard@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{"user" => %{"displayName" => "Lucca"}} = json_response(conn, 200)

      conn =
        build_conn()
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{"error" => %{"code" => "onboarding_already_complete"}} = json_response(conn, 409)
    end

    test "rejects missing dinner slot with onboarding_invalid", %{conn: conn} do
      auth = signup_user("missing-dinner@example.com")

      payload =
        put_in(
          @valid_payload,
          ["slotCookingTimes"],
          Map.delete(@valid_payload["slotCookingTimes"], "dinner")
        )

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"error" => %{"code" => "onboarding_invalid"}} = json_response(conn, 422)
    end

    test "rejects unknown diet with onboarding_invalid", %{conn: conn} do
      auth = signup_user("bad-diet@example.com")
      payload = put_in(@valid_payload, ["preferences", "diet"], "made-up-diet")

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"error" => %{"code" => "onboarding_invalid"}} = json_response(conn, 422)
    end

    test "rejects invalid cookingSkill with onboarding_invalid", %{conn: conn} do
      auth = signup_user("bad-skill@example.com")
      payload = put_in(@valid_payload, ["profile", "cookingSkill"], "wizard")

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"error" => %{"code" => "onboarding_invalid"}} = json_response(conn, 422)
    end

    test "rejects whitespace-only displayName with onboarding_invalid", %{conn: conn} do
      auth = signup_user("blank-display-name@example.com")
      payload = put_in(@valid_payload, ["profile", "displayName"], "   ")

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"error" => %{"code" => "onboarding_invalid"}} = json_response(conn, 422)
    end

    test "returns onboarding_already_complete for invalid retry after completion", %{conn: conn} do
      auth = signup_user("invalid-retry-onboard@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{"user" => %{"displayName" => "Lucca"}} = json_response(conn, 200)

      invalid_retry_payload =
        @valid_payload
        |> put_in(["profile", "displayName"], "   ")
        |> put_in(["preferences", "diet"], "made-up-diet")
        |> update_in(["slotCookingTimes"], &Map.delete(&1, "dinner"))

      conn =
        build_conn()
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", invalid_retry_payload)

      assert %{"error" => %{"code" => "onboarding_already_complete"}} = json_response(conn, 409)
    end

    test "ignores malicious userId/user_id in nested preferences and slot data", %{conn: conn} do
      me = signup_user("malicious-onboard-me@example.com")
      other = signup_user("malicious-onboard-other@example.com")
      other_user_id = other.me.user.id

      payload =
        @valid_payload
        |> put_in(["preferences", "userId"], other_user_id)
        |> put_in(["preferences", "user_id"], other_user_id)
        |> put_in(["slotCookingTimes", "breakfast", "userId"], other_user_id)
        |> put_in(["slotCookingTimes", "lunch", "user_id"], other_user_id)
        |> put_in(["slotCookingTimes", "dinner", "userId"], other_user_id)

      conn =
        conn
        |> auth_conn(me)
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"preferences" => %{"diet" => "omnivore"}} = json_response(conn, 200)
      assert Repo.get_by(UserPreferences, user_id: other_user_id) == nil
      assert Repo.all(from row in UserSlotCookingTime, where: row.user_id == ^other_user_id) == []
    end

    test "succeeds after preferences and slot cooking times were saved before completion", %{
      conn: conn
    } do
      auth = signup_user("pre-saved-onboard@example.com")

      preferences_conn =
        build_conn()
        |> auth_conn(auth)
        |> put(~p"/api/me/preferences", %{
          "diet" => "vegetarian",
          "hardRestrictions" => ["gluten"],
          "softPreferences" => ["beans"]
        })

      assert %{"diet" => "vegetarian"} = json_response(preferences_conn, 200)

      slots_conn =
        build_conn()
        |> auth_conn(auth)
        |> put(~p"/api/me/slot-cooking-times", %{
          "breakfast" => %{"cookingTimeMinutes" => 5, "hungerLevel" => "light"},
          "lunch" => %{"cookingTimeMinutes" => 15, "hungerLevel" => "normal"},
          "dinner" => %{"cookingTimeMinutes" => 25, "hungerLevel" => "strong"}
        })

      assert %{"dinner" => %{"cookingTimeMinutes" => 25}} = json_response(slots_conn, 200)

      conn =
        conn
        |> auth_conn(auth)
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{
               "preferences" => %{"diet" => "omnivore"},
               "slotCookingTimes" => %{
                 "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "light"},
                 "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
                 "dinner" => %{"cookingTimeMinutes" => 45, "hungerLevel" => "strong"}
               }
             } = json_response(conn, 200)

      assert Repo.aggregate(UserPreferences, :count) == 1
      assert Repo.aggregate(UserSlotCookingTime, :count) == 3
    end
  end
end
