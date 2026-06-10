defmodule MyFoodBackWeb.PreferencesControllerTest do
  use MyFoodBackWeb.ConnCase, async: true

  alias MyFoodBack.Auth
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
      auth = signup("no-prefs@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me/preferences")

      assert %{
               "diet" => nil,
               "hardRestrictions" => [],
               "softPreferences" => []
             } = json_response(conn, 200)
    end

    test "locked account can still read preferences", %{conn: conn} do
      auth = signup("locked-prefs@example.com")
      force_account_lock(auth)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me/preferences")

      assert %{"diet" => nil} = json_response(conn, 200)
    end

    test "cross-user isolation: another user's prefs are not visible", %{conn: _conn} do
      me = signup("me-prefs@example.com")
      other = signup("other-prefs@example.com")

      conn1 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{me.access_token}")
        |> put(~p"/api/me/preferences", @valid_payload)

      assert %{"diet" => "omnivore"} = json_response(conn1, 200)

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{other.access_token}")
        |> get(~p"/api/me/preferences")

      assert %{"diet" => nil} = json_response(conn2, 200)
    end
  end

  describe "PUT /api/me/preferences" do
    test "creates a row for a user with no preferences and returns the canonical shape", %{
      conn: conn
    } do
      auth = signup("create-prefs@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/preferences", @valid_payload)

      assert %{
               "diet" => "omnivore",
               "hardRestrictions" => ["peanut"],
               "softPreferences" => ["mushrooms"]
             } = json_response(conn, 200)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me/preferences")

      assert %{"diet" => "omnivore"} = json_response(conn, 200)
    end

    test "updates an existing row", %{conn: conn} do
      auth = signup("update-prefs@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/preferences", @valid_payload)

      assert %{"diet" => "omnivore"} = json_response(conn, 200)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
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
      auth = signup("bad-prefs@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/preferences", %{"diet" => "made-up-diet"})

      assert %{"error" => %{"code" => "preferences_invalid"}} = json_response(conn, 422)
    end

    test "ignores malicious userId/user_id payload keys", %{conn: conn} do
      me = signup("malicious-me-prefs@example.com")
      other = signup("malicious-other-prefs@example.com")
      other_user_id = user_id_from_token(other.access_token)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{me.access_token}")
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
