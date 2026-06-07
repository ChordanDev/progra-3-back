defmodule MyFoodBack.AccountsTest do
  use MyFoodBack.DataCase, async: true

  alias MyFoodBack.Accounts
  alias MyFoodBack.Accounts.{Account, Membership, User}

  describe "create_individual_account/2" do
    test "creates one normalized user, individual account, owner membership, and 10-day trial" do
      now = ~U[2026-06-07 12:00:00Z]

      assert {:ok, %{user: user, account: account, membership: membership}} =
               Accounts.create_individual_account(%{email: "  New.User@Example.COM "}, now: now)

      assert user.email == "new.user@example.com"
      assert is_nil(user.display_name)
      assert is_nil(user.onboarding_completed_at)

      assert account.type == "individual"
      assert account.subscription_status == "none"
      assert account.trial_started_at == now
      assert account.trial_ends_at == DateTime.add(now, 10, :day)

      assert membership.role == "owner"
      assert membership.status == "active"
      assert membership.user_id == user.id
      assert membership.account_id == account.id

      assert Repo.aggregate(User, :count) == 1
      assert Repo.aggregate(Account, :count) == 1
      assert Repo.aggregate(Membership, :count) == 1
    end

    test "enforces normalized unique email" do
      now = ~U[2026-06-07 12:00:00Z]

      assert {:ok, _graph} =
               Accounts.create_individual_account(%{email: "USER@example.com"}, now: now)

      assert {:error, :user, changeset, _changes} =
               Accounts.create_individual_account(%{email: " user@EXAMPLE.com "}, now: now)

      assert %{email: ["has already been taken"]} = errors_on(changeset)
      assert Repo.aggregate(User, :count) == 1
    end

    test "database uniqueness also rejects mixed-case email bypassing changeset normalization" do
      assert {:ok, _user} =
               %User{email: "mixed@example.com"}
               |> Repo.insert()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert_raise Postgrex.Error, fn ->
        Repo.insert_all(User, [
          %{
            id: Ecto.UUID.generate(),
            email: "MIXED@example.com",
            inserted_at: now,
            updated_at: now
          }
        ])
      end
    end
  end

  describe "current account loading" do
    test "loads active owner membership and account for a user" do
      assert {:ok, %{user: user, account: account, membership: membership}} =
               Accounts.create_individual_account(%{email: "owner@example.com"},
                 now: ~U[2026-06-07 12:00:00Z]
               )

      assert {:ok, loaded} = Accounts.get_current_account(user)
      assert loaded.account.id == account.id
      assert loaded.membership.id == membership.id
      assert loaded.membership.role == "owner"
    end

    test "loads the newest active individual membership deterministically" do
      assert {:ok, %{user: user}} =
               Accounts.create_individual_account(%{email: "multi@example.com"},
                 now: ~U[2026-06-07 12:00:00Z]
               )

      newest_account =
        %Account{}
        |> Account.changeset(%{
          type: "individual",
          trial_started_at: ~U[2026-06-08 12:00:00Z],
          trial_ends_at: ~U[2026-06-18 12:00:00Z],
          subscription_status: "none"
        })
        |> Repo.insert!()

      newest_membership =
        %Membership{user_id: user.id, account_id: newest_account.id}
        |> Membership.changeset(%{role: "owner", status: "active"})
        |> Repo.insert!()

      import Ecto.Query

      Repo.update_all(
        from(membership in Membership, where: membership.id != ^newest_membership.id),
        set: [inserted_at: ~U[2026-06-07 12:00:00Z]]
      )

      Repo.update_all(
        from(membership in Membership, where: membership.id == ^newest_membership.id),
        set: [inserted_at: ~U[2026-06-08 12:00:00Z]]
      )

      assert {:ok, loaded} = Accounts.get_current_account(user)
      assert loaded.membership.id == newest_membership.id
    end
  end

  describe "access_state/2" do
    test "allows app usage before trial end and locks at the trial boundary" do
      trial_ends_at = ~U[2026-06-17 12:00:00Z]
      account = %Account{trial_ends_at: trial_ends_at, subscription_status: "none"}

      assert Accounts.access_state(account, ~U[2026-06-17 11:59:59Z]) == %{
               can_use_app: true,
               reason: nil
             }

      assert Accounts.access_state(account, trial_ends_at) == %{
               can_use_app: false,
               reason: "trial_expired"
             }

      assert Accounts.access_state(account, ~U[2026-06-17 12:00:01Z]) == %{
               can_use_app: false,
               reason: "trial_expired"
             }
    end

    test "allows app usage after trial expiration when subscription is active" do
      account = %Account{trial_ends_at: ~U[2026-06-17 12:00:00Z], subscription_status: "active"}

      assert Accounts.access_state(account, ~U[2026-06-18 12:00:00Z]) == %{
               can_use_app: true,
               reason: nil
             }
    end
  end
end
