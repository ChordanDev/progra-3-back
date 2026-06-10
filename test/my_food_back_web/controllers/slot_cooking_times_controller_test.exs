defmodule MyFoodBackWeb.SlotCookingTimesControllerTest do
  use MyFoodBackWeb.ConnCase, async: true

  import Ecto.Query

  alias MyFoodBack.Auth
  alias MyFoodBack.Accounts.UserSlotCookingTime
  alias MyFoodBack.Repo

  @valid_payload %{
    "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "light"},
    "lunch" => %{"cookingTimeMinutes" => 30, "hungerLevel" => "normal"},
    "dinner" => %{"cookingTimeMinutes" => 45, "hungerLevel" => "strong"}
  }

  describe "GET /api/me/slot-cooking-times" do
    test "rejects anonymous requests with 401", %{conn: conn} do
      conn = get(conn, ~p"/api/me/slot-cooking-times")
      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end

    test "returns the three-slot canonical shape with defaults when no rows", %{conn: conn} do
      auth = signup("no-slots@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me/slot-cooking-times")

      assert %{
               "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "lunch" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "dinner" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"}
             } = json_response(conn, 200)
    end

    test "locked account can still read slot cooking times", %{conn: conn} do
      auth = signup("locked-slots@example.com")
      force_account_lock(auth)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me/slot-cooking-times")

      assert %{"breakfast" => %{"cookingTimeMinutes" => 0}} = json_response(conn, 200)
    end

    test "cross-user isolation: another user's slots are not visible", %{conn: _conn} do
      me = signup("me-slots@example.com")
      other = signup("other-slots@example.com")

      conn1 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{me.access_token}")
        |> put(~p"/api/me/slot-cooking-times", @valid_payload)

      assert %{"dinner" => %{"cookingTimeMinutes" => 45}} = json_response(conn1, 200)

      conn2 =
        build_conn()
        |> put_req_header("authorization", "Bearer #{other.access_token}")
        |> get(~p"/api/me/slot-cooking-times")

      assert %{"dinner" => %{"cookingTimeMinutes" => 0}} = json_response(conn2, 200)
    end
  end

  describe "PUT /api/me/slot-cooking-times" do
    test "upserts three rows and returns the canonical shape", %{conn: conn} do
      auth = signup("put-slots@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/slot-cooking-times", @valid_payload)

      assert @valid_payload = json_response(conn, 200)

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me/slot-cooking-times")

      assert @valid_payload = json_response(conn, 200)
    end

    test "rejects unknown slot with slot_cooking_times_invalid", %{conn: conn} do
      auth = signup("bad-slot@example.com")

      bad =
        Map.put(@valid_payload, "snack", %{"cookingTimeMinutes" => 10, "hungerLevel" => "light"})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/slot-cooking-times", bad)

      assert %{"error" => %{"code" => "slot_cooking_times_invalid"}} = json_response(conn, 422)
    end

    test "rejects invalid hunger level with slot_cooking_times_invalid", %{conn: conn} do
      auth = signup("bad-hunger@example.com")
      bad = put_in(@valid_payload, ["lunch", "hungerLevel"], "huge")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/slot-cooking-times", bad)

      assert %{"error" => %{"code" => "slot_cooking_times_invalid"}} = json_response(conn, 422)
    end

    test "rejects negative minutes with slot_cooking_times_invalid", %{conn: conn} do
      auth = signup("neg-mins@example.com")
      bad = put_in(@valid_payload, ["dinner", "cookingTimeMinutes"], -1)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/slot-cooking-times", bad)

      assert %{"error" => %{"code" => "slot_cooking_times_invalid"}} = json_response(conn, 422)
    end

    test "locked account can still update slot cooking times", %{conn: conn} do
      auth = signup("locked-put-slots@example.com")
      force_account_lock(auth)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> put(~p"/api/me/slot-cooking-times", @valid_payload)

      assert @valid_payload = json_response(conn, 200)
    end

    test "ignores malicious userId/user_id nested payload keys", %{conn: conn} do
      me = signup("malicious-me-slots@example.com")
      other = signup("malicious-other-slots@example.com")
      other_user_id = user_id_from_token(other.access_token)

      payload =
        @valid_payload
        |> put_in(["breakfast", "userId"], other_user_id)
        |> put_in(["lunch", "user_id"], other_user_id)
        |> put_in(["dinner", "userId"], other_user_id)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{me.access_token}")
        |> put(~p"/api/me/slot-cooking-times", payload)

      assert @valid_payload = json_response(conn, 200)
      assert Repo.all(from row in UserSlotCookingTime, where: row.user_id == ^other_user_id) == []
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
