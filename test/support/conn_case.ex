defmodule MyFoodBackWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MyFoodBackWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.

  ## Auth helpers

  Controller tests that need an authenticated user can use:

      auth = signup_user("alice@example.com")
      conn = get(auth_conn(conn, auth), ~p"/api/me")

  To exercise the "locked account" branch of the setup endpoints:

      auth = signup_user("locked@example.com")
      lock_current_account(auth)
      conn = get(auth_conn(conn, conn, auth), ~p"/api/me/preferences")
  """

  use ExUnit.CaseTemplate

  import Plug.Conn

  alias MyFoodBack.Accounts.{Account, Membership}
  alias MyFoodBack.Auth
  alias MyFoodBack.Repo

  using do
    quote do
      # The default endpoint for testing
      @endpoint MyFoodBackWeb.Endpoint

      use MyFoodBackWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MyFoodBackWeb.ConnCase
    end
  end

  setup tags do
    MyFoodBack.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Runs the full signup flow for `email` (request code → deliver → verify) and
  returns the auth map produced by `Auth.verify_signup_code/2`.

  The returned map contains at least `:access_token`, `:refresh_token`,
  `:token_type`, and `:me` (with `:user.id`).
  """
  def signup_user(email) when is_binary(email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    assert {:ok, _} = Auth.request_signup_code(%{email: email}, now: now)
    assert_received {:email, email_message}
    [code] = Regex.run(~r/\b\d{6}\b/, email_message.text_body)
    assert {:ok, auth} = Auth.verify_signup_code(%{email: email, code: code}, now: now)
    auth
  end

  @doc """
  Attaches a `Bearer` authorization header to `conn` for the given `auth` map
  (the one returned by `signup_user/1`).
  """
  def auth_conn(conn, %{access_token: access_token}) do
    put_req_header(conn, "authorization", "Bearer #{access_token}")
  end

  @doc """
  Locks the current (active, individual) account for the user behind `auth` by
  pushing its trial end into the past. Setup endpoints (preferences, slot
  cooking times, onboarding) must remain available while the account is in
  access lock; this helper is what tests use to exercise that branch.
  """
  def lock_current_account(%{me: %{user: %{id: user_id}}}) do
    import Ecto.Query

    membership =
      from(m in Membership, where: m.user_id == ^user_id and m.status == "active")
      |> Repo.one!()

    {1, _} =
      Repo.update_all(
        from(a in Account, where: a.id == ^membership.account_id),
        set: [trial_ends_at: ~U[2020-01-01 00:00:00Z]]
      )

    :ok
  end
end
