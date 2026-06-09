defmodule MyFoodBackWeb.AuthControllerTest do
  use MyFoodBackWeb.ConnCase, async: true

  alias MyFoodBack.Accounts
  alias MyFoodBack.Auth

  @now ~U[2026-06-08 12:00:00Z]

  describe "POST /api/auth/signup/request-code" do
    test "requests signup code with camelCase response", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/signup/request-code", %{email: " New@Example.COM "})

      assert %{
               "status" => "code_sent",
               "expiresInSeconds" => 600,
               "resendAvailableInSeconds" => 60
             } = json_response(conn, 200)
    end

    test "returns error envelope for duplicate signup", %{conn: conn} do
      assert {:ok, _graph} =
               Accounts.create_individual_account(%{email: "user@example.com"}, now: @now)

      conn = post(conn, ~p"/api/auth/signup/request-code", %{email: "user@example.com"})

      assert %{"error" => %{"code" => "email_already_exists", "message" => message}} =
               json_response(conn, 409)

      assert is_binary(message)
    end
  end

  describe "POST /api/auth/login/request-code" do
    test "returns email_not_found envelope", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/login/request-code", %{email: "missing@example.com"})

      assert %{"error" => %{"code" => "email_not_found"}} = json_response(conn, 404)
    end
  end

  describe "auth verification, refresh, and logout" do
    test "signup request-code -> verify-code returns tokens and me snapshot", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/signup/request-code", %{email: "new@example.com"})
      assert json_response(conn, 200)["status"] == "code_sent"
      code = delivered_code()

      conn =
        post(build_conn(), ~p"/api/auth/signup/verify-code", %{
          email: "new@example.com",
          code: code,
          deviceId: "ios-1"
        })

      assert %{
               "accessToken" => access_token,
               "refreshToken" => refresh_token,
               "tokenType" => "Bearer",
               "me" => %{
                 "user" => %{"email" => "new@example.com", "displayName" => nil},
                 "account" => %{
                   "type" => "individual",
                   "trialEndsAt" => trial_ends_at,
                   "subscriptionStatus" => "none",
                   "access" => %{"canUseApp" => true, "reason" => nil}
                 },
                 "membership" => %{"role" => "owner"},
                 "onboarding" => %{"isComplete" => false}
               }
             } = json_response(conn, 200)

      assert is_binary(access_token)
      assert is_binary(refresh_token)
      assert is_binary(trial_ends_at)
    end

    test "login verify returns a device session for an existing user", %{conn: conn} do
      assert {:ok, _graph} =
               Accounts.create_individual_account(%{email: "user@example.com"}, now: @now)

      conn = post(conn, ~p"/api/auth/login/request-code", %{email: "user@example.com"})
      assert json_response(conn, 200)["status"] == "code_sent"
      code = delivered_code()

      conn =
        post(build_conn(), ~p"/api/auth/login/verify-code", %{
          "email" => "user@example.com",
          "code" => code,
          "deviceId" => "ios-login"
        })

      assert %{"accessToken" => access_token, "refreshToken" => refresh_token, "me" => me} =
               json_response(conn, 200)

      assert is_binary(access_token)
      assert is_binary(refresh_token)
      assert me["user"]["email"] == "user@example.com"
    end

    test "verify-code ignores non-string deviceId without crashing", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/signup/request-code", %{email: "bad-device@example.com"})
      assert json_response(conn, 200)["status"] == "code_sent"
      code = delivered_code()

      conn =
        post(build_conn(), ~p"/api/auth/signup/verify-code", %{
          email: "bad-device@example.com",
          code: code,
          deviceId: 123
        })

      assert %{"accessToken" => access_token, "refreshToken" => refresh_token} =
               json_response(conn, 200)

      assert is_binary(access_token)
      assert is_binary(refresh_token)
    end

    test "refresh rotates tokens and logout requires bearer auth", %{conn: conn} do
      auth = signup_via_context("refresh@example.com")

      conn = post(conn, ~p"/api/auth/refresh", %{refreshToken: auth.refresh_token})

      assert %{
               "accessToken" => access_token,
               "refreshToken" => refresh_token,
               "tokenType" => "Bearer"
             } =
               json_response(conn, 200)

      assert refresh_token != auth.refresh_token

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{access_token}")
        |> post(~p"/api/auth/logout", %{refreshToken: refresh_token})

      assert response(conn, 204) == ""
    end

    test "logout rejects a refresh token from a different bearer session", %{conn: conn} do
      first = signup_via_context("mismatch@example.com")
      second = login_via_context("mismatch@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{first.access_token}")
        |> post(~p"/api/auth/logout", %{refreshToken: second.refresh_token})

      assert %{"error" => %{"code" => "refresh_token_session_mismatch"}} =
               json_response(conn, 401)

      assert {:ok, _token} = Auth.refresh_session(second.refresh_token, now: @now)
    end

    test "logout without refresh token revokes the authenticated session", %{conn: conn} do
      auth = signup_via_context("current-logout@example.com")

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{auth.access_token}")
        |> post(~p"/api/auth/logout", %{})

      assert response(conn, 204) == ""

      assert {:error, %{code: "refresh_token_revoked"}} =
               Auth.refresh_session(auth.refresh_token, now: now())
    end

    test "logout rejects non-string refresh token without crashing", %{conn: conn} do
      auth = signup_via_context("bad-token@example.com")

      for params <- [%{refreshToken: 123}] do
        conn =
          conn
          |> recycle()
          |> put_req_header("authorization", "Bearer #{auth.access_token}")
          |> post(~p"/api/auth/logout", params)

        assert %{"error" => %{"code" => "refresh_token_invalid"}} = json_response(conn, 401)
      end
    end

    test "verification errors map to stable envelopes", %{conn: conn} do
      assert {:ok, _} = Auth.request_signup_code(%{email: "invalid@example.com"}, now: now())

      conn =
        post(conn, ~p"/api/auth/signup/verify-code", %{
          email: "invalid@example.com",
          code: "000000"
        })

      assert %{"error" => %{"code" => "code_invalid"}} = json_response(conn, 422)

      for _attempt <- 1..4 do
        post(build_conn(), ~p"/api/auth/signup/verify-code", %{
          email: "invalid@example.com",
          code: "000000"
        })
      end

      conn =
        post(build_conn(), ~p"/api/auth/signup/verify-code", %{
          email: "invalid@example.com",
          code: "000000"
        })

      assert %{"error" => %{"code" => "too_many_attempts"}} = json_response(conn, 422)
    end

    test "expired code and rate limit errors map to stable envelopes", %{conn: conn} do
      assert {:ok, _} = Auth.request_signup_code(%{email: "expired@example.com"}, now: @now)
      code = delivered_code()

      import Ecto.Query

      MyFoodBack.Auth.EmailCode
      |> where([code], code.email == "expired@example.com")
      |> MyFoodBack.Repo.one!()
      |> MyFoodBack.Auth.EmailCode.changeset(%{expires_at: ~U[2000-01-01 00:00:00Z]})
      |> MyFoodBack.Repo.update!()

      conn =
        post(conn, ~p"/api/auth/signup/verify-code", %{
          email: "expired@example.com",
          code: code
        })

      assert %{"error" => %{"code" => "code_expired"}} = json_response(conn, 422)

      conn =
        post(build_conn(), ~p"/api/auth/signup/request-code", %{email: "limited@example.com"})

      assert json_response(conn, 200)["status"] == "code_sent"

      conn =
        post(build_conn(), ~p"/api/auth/signup/request-code", %{email: "limited@example.com"})

      assert %{"error" => %{"code" => "rate_limited"}} = json_response(conn, 429)
    end
  end

  defp delivered_code do
    assert_received {:email, email}
    [code] = Regex.run(~r/\b\d{6}\b/, email.text_body)
    code
  end

  defp signup_via_context(email) do
    now = now()
    assert {:ok, _} = Auth.request_signup_code(%{email: email}, now: now)
    code = delivered_code()
    assert {:ok, auth} = Auth.verify_signup_code(%{email: email, code: code}, now: now)
    auth
  end

  defp login_via_context(email) do
    now = now() |> DateTime.add(61, :second)
    assert {:ok, _} = Auth.request_login_code(%{email: email}, now: now)
    code = delivered_code()
    assert {:ok, auth} = Auth.verify_login_code(%{email: email, code: code}, now: now)
    auth
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
