defmodule MyFoodBackWeb.OnboardingControllerTest do
  use MyFoodBackWeb.ConnCase, async: true

  import Ecto.Query

  alias MyFoodBack.Auth
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
      auth = signup("onboard-controller@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
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
      auth = signup("locked-onboard@example.com")

      force_account_lock(auth)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{
               "user" => %{"displayName" => "Lucca"}
             } = json_response(conn, 200)
    end

    test "rejects a second submission with onboarding_already_complete (idempotency)", %{
      conn: conn
    } do
      auth = signup("dup-onboard@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{"user" => %{"displayName" => "Lucca"}} = json_response(conn, 200)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{"error" => %{"code" => "onboarding_already_complete"}} = json_response(conn, 409)
    end

    test "rejects missing dinner slot with onboarding_invalid", %{conn: conn} do
      auth = signup("missing-dinner@example.com")

      payload =
        put_in(
          @valid_payload,
          ["slotCookingTimes"],
          Map.delete(@valid_payload["slotCookingTimes"], "dinner")
        )

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"error" => %{"code" => "onboarding_invalid"}} = json_response(conn, 422)
    end

    test "rejects unknown diet with onboarding_invalid", %{conn: conn} do
      auth = signup("bad-diet@example.com")
      payload = put_in(@valid_payload, ["preferences", "diet"], "made-up-diet")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"error" => %{"code" => "onboarding_invalid"}} = json_response(conn, 422)
    end

    test "rejects invalid cookingSkill with onboarding_invalid", %{conn: conn} do
      auth = signup("bad-skill@example.com")
      payload = put_in(@valid_payload, ["profile", "cookingSkill"], "wizard")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"error" => %{"code" => "onboarding_invalid"}} = json_response(conn, 422)
    end

    test "rejects whitespace-only displayName with onboarding_invalid", %{conn: conn} do
      auth = signup("blank-display-name@example.com")
      payload = put_in(@valid_payload, ["profile", "displayName"], "   ")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"error" => %{"code" => "onboarding_invalid"}} = json_response(conn, 422)
    end

    test "returns onboarding_already_complete for invalid retry after completion", %{conn: conn} do
      auth = signup("invalid-retry-onboard@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", @valid_payload)

      assert %{"user" => %{"displayName" => "Lucca"}} = json_response(conn, 200)

      invalid_retry_payload =
        @valid_payload
        |> put_in(["profile", "displayName"], "   ")
        |> put_in(["preferences", "diet"], "made-up-diet")
        |> update_in(["slotCookingTimes"], &Map.delete(&1, "dinner"))

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/onboarding/complete", invalid_retry_payload)

      assert %{"error" => %{"code" => "onboarding_already_complete"}} = json_response(conn, 409)
    end

    test "ignores malicious userId/user_id in nested preferences and slot data", %{conn: conn} do
      me = signup("malicious-onboard-me@example.com")
      other = signup("malicious-onboard-other@example.com")
      other_user_id = user_id_from_token(other.access_token)

      payload =
        @valid_payload
        |> put_in(["preferences", "userId"], other_user_id)
        |> put_in(["preferences", "user_id"], other_user_id)
        |> put_in(["slotCookingTimes", "breakfast", "userId"], other_user_id)
        |> put_in(["slotCookingTimes", "lunch", "user_id"], other_user_id)
        |> put_in(["slotCookingTimes", "dinner", "userId"], other_user_id)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{me.access_token}")
        |> post(~p"/api/onboarding/complete", payload)

      assert %{"preferences" => %{"diet" => "omnivore"}} = json_response(conn, 200)
      assert Repo.get_by(UserPreferences, user_id: other_user_id) == nil
      assert Repo.all(from row in UserSlotCookingTime, where: row.user_id == ^other_user_id) == []
    end

    test "succeeds after preferences and slot cooking times were saved before completion", %{
      conn: conn
    } do
      auth = signup("pre-saved-onboard@example.com")

      preferences_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/preferences", %{
          "diet" => "vegetarian",
          "hardRestrictions" => ["gluten"],
          "softPreferences" => ["beans"]
        })

      assert %{"diet" => "vegetarian"} = json_response(preferences_conn, 200)

      slots_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/slot-cooking-times", %{
          "breakfast" => %{"cookingTimeMinutes" => 5, "hungerLevel" => "light"},
          "lunch" => %{"cookingTimeMinutes" => 15, "hungerLevel" => "normal"},
          "dinner" => %{"cookingTimeMinutes" => 25, "hungerLevel" => "strong"}
        })

      assert %{"dinner" => %{"cookingTimeMinutes" => 25}} = json_response(slots_conn, 200)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
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

  defp signup(email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    assert {:ok, _} = Auth.request_signup_code(%{email: email}, now: now)

    assert_received {:email, email_message}
    [code] = Regex.run(~r/\b\d{6}\b/, email_message.text_body)
    assert {:ok, auth} = Auth.verify_signup_code(%{email: email, code: code}, now: now)
    auth
  end

  defp force_account_lock(auth) do
    import Ecto.Query

    user_id = user_id_from_token(auth.access_token)

    m =
      from(m in MyFoodBack.Accounts.Membership,
        where: m.user_id == ^user_id and m.status == "active"
      )
      |> Repo.one!()

    Repo.update_all(
      from(a in MyFoodBack.Accounts.Account, where: a.id == ^m.account_id),
      set: [trial_ends_at: ~U[2020-01-01 00:00:00Z]]
    )
  end

  defp user_id_from_token(access_token) do
    Auth.verify_access_token(access_token,
      now: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> elem(1)
    |> Map.get(:user_id)
  end
end
