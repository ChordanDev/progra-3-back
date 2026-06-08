defmodule MyFoodBack.Auth.SessionTest do
  use MyFoodBack.DataCase, async: true

  alias MyFoodBack.Accounts
  alias MyFoodBack.Auth
  alias MyFoodBack.Auth.Session
  alias MyFoodBack.Repo

  @now ~U[2026-06-07 12:00:00Z]

  describe "signup verification sessions" do
    test "valid signup code creates account graph and session material" do
      assert {:ok, _} = Auth.request_signup_code(%{email: "new@example.com"}, now: @now)
      code = delivered_code()

      assert {:ok, auth} =
               Auth.verify_signup_code(
                 %{email: "new@example.com", code: code, device_id: "ios-1"},
                 now: @now,
                 ip: "127.0.0.1",
                 user_agent: "Expo/iOS"
               )

      assert auth.token_type == "Bearer"
      assert is_binary(auth.access_token)
      assert is_binary(auth.refresh_token)
      assert auth.me.user.email == "new@example.com"
      assert auth.me.account.type == "individual"
      assert auth.me.account.access.can_use_app == true
      assert auth.me.membership.role == "owner"
      assert auth.me.onboarding.is_complete == false

      session = Repo.one!(Session)
      assert session.user_id == auth.me.user.id
      assert session.expires_at == DateTime.add(@now, 30, :day)
      assert is_binary(session.refresh_token_hash)
      refute session.refresh_token_hash == auth.refresh_token
      refute is_nil(session.device_id_hash)
      refute is_nil(session.ip_hash)
    end

    test "locked account can still login and receive locked access state" do
      expired_now = ~U[2026-06-27 12:00:00Z]

      assert {:ok, %{user: user, account: account}} =
               Accounts.create_individual_account(%{email: "locked@example.com"}, now: @now)

      account
      |> Ecto.Changeset.change(trial_ends_at: ~U[2026-06-17 12:00:00Z])
      |> Repo.update!()

      assert {:ok, _} = Auth.request_login_code(%{email: user.email}, now: expired_now)
      code = delivered_code()

      assert {:ok, auth} =
               Auth.verify_login_code(%{email: user.email, code: code, device_id: "ios-locked"},
                 now: expired_now
               )

      assert auth.me.account.access == %{can_use_app: false, reason: "trial_expired"}
    end
  end

  describe "login sessions and refresh" do
    test "second-device login preserves first session" do
      assert {:ok, %{user: user}} =
               Accounts.create_individual_account(%{email: "multi@example.com"}, now: @now)

      first = login(user.email, "device-a", @now)
      second = login(user.email, "device-b", DateTime.add(@now, 61, :second))

      assert first.refresh_token != second.refresh_token
      assert Repo.aggregate(Session, :count) == 2

      assert {:ok, _} =
               Auth.refresh_session(first.refresh_token, now: DateTime.add(@now, 2, :minute))

      assert {:ok, _} =
               Auth.refresh_session(second.refresh_token, now: DateTime.add(@now, 2, :minute))
    end

    test "valid refresh rotates refresh token and old token is rejected" do
      assert {:ok, %{user: user}} =
               Accounts.create_individual_account(%{email: "rotate@example.com"}, now: @now)

      auth = login(user.email, "device-a", @now)

      assert {:ok, refreshed} =
               Auth.refresh_session(auth.refresh_token, now: DateTime.add(@now, 5, :minute))

      assert is_binary(refreshed.access_token)
      assert is_binary(refreshed.refresh_token)
      assert refreshed.refresh_token != auth.refresh_token

      assert {:error, %{code: "refresh_token_replayed"}} =
               Auth.refresh_session(auth.refresh_token, now: DateTime.add(@now, 6, :minute))

      assert {:ok, _} =
               Auth.refresh_session(refreshed.refresh_token, now: DateTime.add(@now, 7, :minute))
    end

    test "revoked, rotated, and expired refresh tokens are rejected with stable errors" do
      assert {:ok, %{user: user}} =
               Accounts.create_individual_account(%{email: "reject@example.com"}, now: @now)

      auth = login(user.email, "device-a", @now)
      assert :ok = Auth.logout(auth.refresh_token, now: DateTime.add(@now, 1, :minute))

      assert {:error, %{code: "refresh_token_revoked"}} =
               Auth.refresh_session(auth.refresh_token, now: DateTime.add(@now, 2, :minute))

      rotated = login(user.email, "device-b", DateTime.add(@now, 61, :second))

      assert {:ok, _refreshed} =
               Auth.refresh_session(rotated.refresh_token, now: DateTime.add(@now, 2, :minute))

      assert {:error, %{code: "refresh_token_replayed"}} =
               Auth.logout(rotated.refresh_token, now: DateTime.add(@now, 3, :minute))

      expired = login(user.email, "device-c", DateTime.add(@now, 122, :second))

      assert {:error, %{code: "refresh_token_expired"}} =
               Auth.refresh_session(expired.refresh_token, now: DateTime.add(@now, 31, :day))
    end

    test "long user agents do not crash session creation" do
      assert {:ok, %{user: user}} =
               Accounts.create_individual_account(%{email: "agent@example.com"}, now: @now)

      auth = login(user.email, "device-a", @now, String.duplicate("A", 1_000))

      assert is_binary(auth.refresh_token)
      assert Repo.one!(Session).user_agent |> String.length() == 255
    end

    test "logout revokes only current session" do
      assert {:ok, %{user: user}} =
               Accounts.create_individual_account(%{email: "logout@example.com"}, now: @now)

      first = login(user.email, "device-a", @now)
      second = login(user.email, "device-b", DateTime.add(@now, 61, :second))

      assert :ok = Auth.logout(first.refresh_token, now: DateTime.add(@now, 2, :minute))

      assert {:error, %{code: "refresh_token_revoked"}} =
               Auth.refresh_session(first.refresh_token, now: DateTime.add(@now, 3, :minute))

      assert {:ok, _} =
               Auth.refresh_session(second.refresh_token, now: DateTime.add(@now, 3, :minute))
    end
  end

  defp login(email, device_id, now, user_agent \\ nil) do
    assert {:ok, _} = Auth.request_login_code(%{email: email}, now: now)
    code = delivered_code()

    assert {:ok, auth} =
             Auth.verify_login_code(%{email: email, code: code, device_id: device_id},
               now: now,
               user_agent: user_agent
             )

    auth
  end

  defp delivered_code do
    assert_received {:email, email}
    [code] = Regex.run(~r/\b\d{6}\b/, email.text_body)
    code
  end
end
