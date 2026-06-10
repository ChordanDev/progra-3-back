defmodule MyFoodBackWeb.MeControllerTest do
  use MyFoodBackWeb.ConnCase, async: true

  alias MyFoodBack.Accounts.Account
  alias MyFoodBack.Auth
  alias MyFoodBack.Repo

  describe "GET /api/me" do
    test "rejects unauthenticated requests", %{conn: conn} do
      conn = get(conn, ~p"/api/me")

      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end

    test "locked account can still call /api/me", %{conn: conn} do
      auth = signup("locked-me@example.com", now())

      Account
      |> Repo.one!()
      |> Account.changeset(%{trial_ends_at: ~U[2026-05-11 12:00:00Z]})
      |> Repo.update!()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me")

      assert %{"account" => %{"access" => %{"canUseApp" => false}}} = json_response(conn, 200)
    end

    test "returns current user snapshot without full preferences", %{conn: conn} do
      auth = signup("active@example.com", now())

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me")

      assert %{
               "user" => %{"id" => user_id, "email" => "active@example.com", "displayName" => nil},
               "account" => %{
                 "id" => account_id,
                 "type" => "individual",
                 "trialEndsAt" => trial_ends_at,
                 "subscriptionStatus" => "none",
                 "access" => %{"canUseApp" => true, "reason" => nil}
               },
               "membership" => %{"role" => "owner"},
               "onboarding" => %{"isComplete" => false}
             } = response = json_response(conn, 200)

      assert is_binary(user_id)
      assert is_binary(account_id)
      assert is_binary(trial_ends_at)
      refute Map.has_key?(response, "preferences")
    end

    test "returns trial_expired access lock", %{conn: conn} do
      auth = signup("locked@example.com", now())

      Account
      |> Repo.one!()
      |> Account.changeset(%{trial_ends_at: ~U[2026-05-11 12:00:00Z]})
      |> Repo.update!()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me")

      assert %{"account" => %{"access" => %{"canUseApp" => false, "reason" => "trial_expired"}}} =
               json_response(conn, 200)
    end

    test "active subscription overrides expired trial lock", %{conn: conn} do
      auth = signup("paid@example.com", now())

      Account
      |> Repo.one!()
      |> Account.changeset(%{
        trial_ends_at: ~U[2026-05-11 12:00:00Z],
        subscription_status: "active"
      })
      |> Repo.update!()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> get(~p"/api/me")

      assert %{"account" => %{"access" => %{"canUseApp" => true, "reason" => nil}}} =
               json_response(conn, 200)
    end
  end

  defp signup(email, now) do
    assert {:ok, _} = Auth.request_signup_code(%{email: email}, now: now)
    assert_received {:email, email_message}
    [code] = Regex.run(~r/\b\d{6}\b/, email_message.text_body)
    assert {:ok, auth} = Auth.verify_signup_code(%{email: email, code: code}, now: now)
    auth
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
