defmodule MyFoodBackWeb.SlotCookingTimesControllerTest do
  use MyFoodBackWeb.ConnCase, async: true

  import Ecto.Query

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
      auth = signup_user("no-slots@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> get(~p"/api/me/slot-cooking-times")

      assert %{
               "breakfast" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "lunch" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"},
               "dinner" => %{"cookingTimeMinutes" => 0, "hungerLevel" => "normal"}
             } = json_response(conn, 200)
    end

    test "locked account can still read slot cooking times", %{conn: conn} do
      auth = signup_user("locked-slots@example.com")
      lock_current_account(auth)

      conn =
        conn
        |> auth_conn(auth)
        |> get(~p"/api/me/slot-cooking-times")

      assert %{"breakfast" => %{"cookingTimeMinutes" => 0}} = json_response(conn, 200)
    end

    test "cross-user isolation: another user's slots are not visible", %{conn: _conn} do
      me = signup_user("me-slots@example.com")
      other = signup_user("other-slots@example.com")

      conn1 =
        build_conn()
        |> auth_conn(me)
        |> put(~p"/api/me/slot-cooking-times", @valid_payload)

      assert %{"dinner" => %{"cookingTimeMinutes" => 45}} = json_response(conn1, 200)

      conn2 =
        build_conn()
        |> auth_conn(other)
        |> get(~p"/api/me/slot-cooking-times")

      assert %{"dinner" => %{"cookingTimeMinutes" => 0}} = json_response(conn2, 200)
    end
  end

  describe "PUT /api/me/slot-cooking-times" do
    test "upserts three rows and returns the canonical shape", %{conn: conn} do
      auth = signup_user("put-slots@example.com")

      conn =
        conn
        |> auth_conn(auth)
        |> put(~p"/api/me/slot-cooking-times", @valid_payload)

      assert @valid_payload = json_response(conn, 200)

      conn =
        build_conn()
        |> auth_conn(auth)
        |> get(~p"/api/me/slot-cooking-times")

      assert @valid_payload = json_response(conn, 200)
    end

    test "rejects unknown slot with slot_cooking_times_invalid", %{conn: conn} do
      auth = signup_user("bad-slot@example.com")

      bad =
        Map.put(@valid_payload, "snack", %{"cookingTimeMinutes" => 10, "hungerLevel" => "light"})

      conn =
        conn
        |> auth_conn(auth)
        |> put(~p"/api/me/slot-cooking-times", bad)

      assert %{"error" => %{"code" => "slot_cooking_times_invalid"}} = json_response(conn, 422)
    end

    test "rejects invalid hunger level with slot_cooking_times_invalid", %{conn: conn} do
      auth = signup_user("bad-hunger@example.com")
      bad = put_in(@valid_payload, ["lunch", "hungerLevel"], "huge")

      conn =
        conn
        |> auth_conn(auth)
        |> put(~p"/api/me/slot-cooking-times", bad)

      assert %{"error" => %{"code" => "slot_cooking_times_invalid"}} = json_response(conn, 422)
    end

    test "rejects negative minutes with slot_cooking_times_invalid", %{conn: conn} do
      auth = signup_user("neg-mins@example.com")
      bad = put_in(@valid_payload, ["dinner", "cookingTimeMinutes"], -1)

      conn =
        conn
        |> auth_conn(auth)
        |> put(~p"/api/me/slot-cooking-times", bad)

      assert %{"error" => %{"code" => "slot_cooking_times_invalid"}} = json_response(conn, 422)
    end

    test "locked account can still update slot cooking times", %{conn: conn} do
      auth = signup_user("locked-put-slots@example.com")
      lock_current_account(auth)

      conn =
        conn
        |> auth_conn(auth)
        |> put(~p"/api/me/slot-cooking-times", @valid_payload)

      assert @valid_payload = json_response(conn, 200)
    end

    test "ignores malicious userId/user_id nested payload keys", %{conn: conn} do
      me = signup_user("malicious-me-slots@example.com")
      other = signup_user("malicious-other-slots@example.com")
      other_user_id = other.me.user.id

      payload =
        @valid_payload
        |> put_in(["breakfast", "userId"], other_user_id)
        |> put_in(["lunch", "user_id"], other_user_id)
        |> put_in(["dinner", "userId"], other_user_id)

      conn =
        conn
        |> auth_conn(me)
        |> put(~p"/api/me/slot-cooking-times", payload)

      assert @valid_payload = json_response(conn, 200)
      assert Repo.all(from row in UserSlotCookingTime, where: row.user_id == ^other_user_id) == []
    end
  end
end
