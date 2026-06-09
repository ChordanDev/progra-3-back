defmodule MyFoodBack.Auth.EmailCodeTest do
  use MyFoodBack.DataCase, async: true

  import Swoosh.TestAssertions

  alias MyFoodBack.Accounts
  alias MyFoodBack.Accounts.User
  alias MyFoodBack.Auth
  alias MyFoodBack.Auth.EmailCode
  alias MyFoodBack.RateLimits.Event

  @now ~U[2026-06-07 12:00:00Z]

  describe "signup code requests" do
    test "stores only a hashed six digit code, sends code, and does not create a user" do
      assert {:ok, response} =
               Auth.request_signup_code(%{email: " New@Example.COM "},
                 now: @now,
                 ip: "127.0.0.1",
                 device_id: "device-a"
               )

      assert response == %{
               status: "code_sent",
               expires_in_seconds: 600,
               resend_available_in_seconds: 60
             }

      assert Repo.aggregate(User, :count) == 0

      email_code = Repo.one!(EmailCode)
      assert email_code.email == "new@example.com"
      assert email_code.flow == "signup"
      assert email_code.expires_at == DateTime.add(@now, 10, :minute)
      assert email_code.last_sent_at == @now
      assert email_code.attempt_count == 0
      assert is_binary(email_code.code_hash)
      refute email_code.code_hash =~ ~r/^\d{6}$/
      refute is_nil(email_code.request_ip_hash)
      refute is_nil(email_code.device_id_hash)

      assert_email_sent(fn email ->
        assert email.to == [{"", "new@example.com"}]
        assert email.from == {"Meal Planner", "no-reply@example.com"}
        assert email.subject =~ "code"
        assert email.text_body =~ "Your access code is"
        assert email.text_body =~ ~r/\b\d{6}\b/
      end)
    end

    test "rejects missing or invalid signup email with a stable error" do
      assert {:error, %{code: "invalid_email"}} = Auth.request_signup_code(%{}, now: @now)

      assert {:error, %{code: "invalid_email"}} =
               Auth.request_signup_code(%{email: "not-an-email"}, now: @now)
    end

    test "rejects duplicate signup email" do
      assert {:ok, _graph} =
               Accounts.create_individual_account(%{email: "user@example.com"}, now: @now)

      assert {:error, %{code: "email_already_exists"}} =
               Auth.request_signup_code(%{email: " USER@example.com "}, now: @now)
    end

    test "enforces resend cooldown" do
      assert {:ok, _response} =
               Auth.request_signup_code(%{email: "cooldown@example.com"}, now: @now)

      assert {:error, %{code: "rate_limited"}} =
               Auth.request_signup_code(%{email: "cooldown@example.com"},
                 now: DateTime.add(@now, 59, :second)
               )
    end

    test "returns stable rate_limited code after request limit is exceeded" do
      email = "limit@example.com"

      for minutes <- [0, 2, 4] do
        assert {:ok, _response} =
                 Auth.request_signup_code(%{email: email},
                   now: DateTime.add(@now, minutes, :minute)
                 )
      end

      assert {:error, %{code: "rate_limited"}} =
               Auth.request_signup_code(%{email: email}, now: DateTime.add(@now, 6, :minute))
    end
  end

  describe "login code requests" do
    test "rejects missing or invalid login email with a stable error" do
      assert {:error, %{code: "invalid_email"}} = Auth.request_login_code(%{}, now: @now)

      assert {:error, %{code: "invalid_email"}} =
               Auth.request_login_code(%{email: "not-an-email"}, now: @now)
    end

    test "requires an existing user" do
      assert {:error, %{code: "email_not_found"}} =
               Auth.request_login_code(%{email: "missing@example.com"}, now: @now)
    end

    test "uses the same security rules without cross-invalidating signup codes" do
      assert {:ok, _graph} =
               Accounts.create_individual_account(%{email: "user@example.com"}, now: @now)

      assert {:ok, _signup} =
               Auth.request_signup_code(%{email: "signup-only@example.com"}, now: @now)

      assert {:ok, _login} = Auth.request_login_code(%{email: "user@example.com"}, now: @now)

      assert Repo.aggregate(
               from(c in EmailCode, where: c.flow == "signup" and is_nil(c.invalidated_at)),
               :count
             ) == 1

      assert Repo.aggregate(
               from(c in EmailCode, where: c.flow == "login" and is_nil(c.invalidated_at)),
               :count
             ) == 1
    end
  end

  describe "code verification primitives" do
    test "valid code consumes the latest active code and returns session material" do
      assert {:ok, _response} =
               Auth.request_signup_code(%{email: "verify@example.com"}, now: @now)

      code = delivered_code()

      assert {:ok, auth} =
               Auth.verify_signup_code(%{email: "verify@example.com", code: code}, now: @now)

      assert auth.token_type == "Bearer"
      assert is_binary(auth.access_token)
      assert is_binary(auth.refresh_token)
      assert Repo.one!(EmailCode).consumed_at == @now

      assert {:error, %{code: "code_invalid"}} =
               Auth.verify_signup_code(%{email: "verify@example.com", code: code}, now: @now)
    end

    test "rejects expired codes" do
      assert {:ok, _response} =
               Auth.request_signup_code(%{email: "expired@example.com"}, now: @now)

      code = delivered_code()

      assert {:error, %{code: "code_expired"}} =
               Auth.verify_signup_code(%{email: "expired@example.com", code: code},
                 now: DateTime.add(@now, 10, :minute)
               )
    end

    test "invalid code increments attempts and the sixth failed attempt is capped" do
      assert {:ok, _response} =
               Auth.request_signup_code(%{email: "attempts@example.com"}, now: @now)

      for attempt <- 1..5 do
        assert {:error, %{code: "code_invalid"}} =
                 Auth.verify_signup_code(%{email: "attempts@example.com", code: "000000"},
                   now: @now
                 )

        assert Repo.one!(EmailCode).attempt_count == attempt
      end

      assert {:error, %{code: "too_many_attempts"}} =
               Auth.verify_signup_code(%{email: "attempts@example.com", code: "000000"},
                 now: @now
               )
    end

    test "records verification attempts for rolling rate limits" do
      assert {:ok, _response} =
               Auth.request_signup_code(%{email: "record-verify@example.com"}, now: @now)

      assert {:error, %{code: "code_invalid"}} =
               Auth.verify_signup_code(%{email: "record-verify@example.com", code: "000000"},
                 now: @now,
                 ip: "127.0.0.10",
                 device_id: "device-record"
               )

      assert Repo.aggregate(
               from(event in Event,
                 where: event.action == "verify_code" and event.scope == "email"
               ),
               :count
             ) == 1

      assert Repo.aggregate(
               from(event in Event,
                 where: event.action == "verify_code" and event.scope == "ip"
               ),
               :count
             ) == 1

      assert Repo.aggregate(
               from(event in Event,
                 where: event.action == "verify_code" and event.scope == "device"
               ),
               :count
             ) == 1
    end

    test "returns rate_limited when email exceeds verification rolling limit" do
      email = "verify-limit@example.com"

      assert {:ok, _response} = Auth.request_signup_code(%{email: email}, now: @now)
      code = delivered_code()

      seed_verify_limit_events(:email, "email:signup:#{email}", 10)

      assert {:error, %{code: "rate_limited"}} =
               Auth.verify_signup_code(%{email: email, code: code}, now: @now)

      email_code = Repo.one!(EmailCode)
      assert email_code.consumed_at == nil
      assert email_code.attempt_count == 0
    end

    test "returns rate_limited when device exceeds verification rolling limit" do
      email = "verify-device-limit@example.com"

      assert {:ok, _response} = Auth.request_signup_code(%{email: email}, now: @now)
      code = delivered_code()

      seed_verify_limit_events(:device, "device-limit", 20)

      assert {:error, %{code: "rate_limited"}} =
               Auth.verify_signup_code(%{email: email, code: code, device_id: "device-limit"},
                 now: @now
               )

      email_code = Repo.one!(EmailCode)
      assert email_code.consumed_at == nil
      assert email_code.attempt_count == 0
    end

    test "new code invalidates the previous code for the same email and flow" do
      assert {:ok, _response} =
               Auth.request_signup_code(%{email: "replace@example.com"}, now: @now)

      old_code = delivered_code()

      assert {:ok, _response} =
               Auth.request_signup_code(%{email: "replace@example.com"},
                 now: DateTime.add(@now, 61, :second)
               )

      new_code = delivered_code()

      assert {:error, %{code: "code_invalid"}} =
               Auth.verify_signup_code(%{email: "replace@example.com", code: old_code},
                 now: DateTime.add(@now, 61, :second)
               )

      assert {:ok, _email_code} =
               Auth.verify_signup_code(%{email: "replace@example.com", code: new_code},
                 now: DateTime.add(@now, 61, :second)
               )
    end
  end

  defp delivered_code do
    assert_received {:email, email}
    [code] = Regex.run(~r/\b\d{6}\b/, email.text_body)
    code
  end

  defp seed_verify_limit_events(scope, raw_key, count) do
    for offset <- 1..count do
      occurred_at = DateTime.add(@now, -offset, :second)

      %Event{}
      |> Event.changeset(%{
        key_hash: MyFoodBack.RateLimits.hash_value(raw_key),
        scope: Atom.to_string(scope),
        action: "verify_code",
        occurred_at: occurred_at
      })
      |> Repo.insert!()
    end
  end
end
