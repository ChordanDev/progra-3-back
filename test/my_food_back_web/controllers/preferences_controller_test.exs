defmodule MyFoodBackWeb.PreferencesControllerTest do
  use MyFoodBackWeb.ConnCase, async: true

  alias MyFoodBack.Accounts.UserPreferences
  alias MyFoodBack.Repo

  @valid_payload %{
    "diet" => "omnivore",
    "hardRestrictions" => ["peanut"],
    "softPreferences" => ["mushrooms"]
  }

  describe "GET /api/me/preferences" do
    test "rejects anonymous requests with 401", %{conn: conn} do
      conn = get(conn, ~p"/api/me/preferences")
      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end

    test "returns defaults for a user with no preferences row", %{conn: conn} do
      auth = signup_user("no-prefs@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> get(~p"/api/me/preferences")

      assert %{
               "diet" => nil,
               "hardRestrictions" => [],
               "softPreferences" => []
             } = json_response(conn, 200)
    end

    test "locked account can still read preferences", %{conn: conn} do
      auth = signup_user("locked-prefs@example.com")
      lock_current_account(auth)

      conn =
        conn
        |> auth_conn(auth)
        |> get(~p"/api/me/preferences")

      assert %{"diet" => nil} = json_response(conn, 200)
    end

    test "cross-user isolation: another user's prefs are not visible", %{conn: _conn} do
      me = signup_user("me-prefs@example.com")
      other = signup_user("other-prefs@example.com")

      conn1 =
        build_conn()
        |> auth_conn(me)
        |> put(~p"/api/me/preferences", @valid_payload)

      assert %{"diet" => "omnivore"} = json_response(conn1, 200)

      conn2 =
        build_conn()
        |> auth_conn(other)
        |> get(~p"/api/me/preferences")

      assert %{"diet" => nil} = json_response(conn2, 200)
    end
  end

  describe "PUT /api/me/preferences" do
    test "creates a row for a user with no preferences and returns the canonical shape", %{
      conn: conn
    } do
      auth = signup_user("create-prefs@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> put(~p"/api/me/preferences", @valid_payload)

      assert %{
               "diet" => "omnivore",
               "hardRestrictions" => ["peanut"],
               "softPreferences" => ["mushrooms"]
             } = json_response(conn, 200)

      conn =
        build_conn()
        |> auth_conn(auth)
        |> get(~p"/api/me/preferences")

      assert %{"diet" => "omnivore"} = json_response(conn, 200)
    end

    test "updates an existing row", %{conn: conn} do
      auth = signup_user("update-prefs@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> put(~p"/api/me/preferences", @valid_payload)

      assert %{"diet" => "omnivore"} = json_response(conn, 200)

      conn =
        build_conn()
        |> auth_conn(auth)
        |> put(~p"/api/me/preferences", %{
          "diet" => "pescatarian",
          "hardRestrictions" => ["shellfish"],
          "softPreferences" => ["cilantro"]
        })

      assert %{
               "diet" => "pescatarian",
               "hardRestrictions" => ["shellfish"],
               "softPreferences" => ["cilantro"]
             } = json_response(conn, 200)
    end

    test "rejects unknown diet code with preferences_invalid", %{conn: conn} do
      auth = signup_user("bad-prefs@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> put(~p"/api/me/preferences", %{"diet" => "made-up-diet"})

      assert %{"error" => %{"code" => "preferences_invalid"}} = json_response(conn, 422)
    end

    test "ignores malicious userId/user_id payload keys", %{conn: conn} do
      me = signup_user("malicious-me-prefs@example.com")
      other = signup_user("malicious-other-prefs@example.com")
      other_user_id = other.me.user.id

      conn =
        conn
        |> auth_conn(me)
        |> put(~p"/api/me/preferences", %{
          "userId" => other_user_id,
          "user_id" => other_user_id,
          "diet" => "omnivore",
          "hardRestrictions" => [],
          "softPreferences" => []
        })

      assert %{"diet" => "omnivore"} = json_response(conn, 200)
      assert Repo.get_by(UserPreferences, user_id: other_user_id) == nil
    end
  end
end
