defmodule MyFoodBack.Accounts do
  import Ecto.Query

  alias Ecto.Multi
  alias MyFoodBack.Accounts.{Account, Membership, User}
  alias MyFoodBack.Repo

  @trial_days 10

  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  def normalize_email(other), do: other

  def create_individual_account(attrs, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    trial_ends_at = DateTime.add(now, @trial_days, :day)

    Multi.new()
    |> Multi.insert(:user, User.changeset(%User{}, attrs))
    |> Multi.insert(:account, fn _changes ->
      Account.changeset(%Account{}, %{
        type: "individual",
        trial_started_at: now,
        trial_ends_at: trial_ends_at,
        subscription_status: "none"
      })
    end)
    |> Multi.insert(:membership, fn %{user: user, account: account} ->
      %Membership{user_id: user.id, account_id: account.id}
      |> Membership.changeset(%{role: "owner", status: "active"})
    end)
    |> Repo.transaction()
  end

  def get_current_account(%User{id: user_id}), do: get_current_account(user_id)

  def get_current_account(user_id) when is_binary(user_id) do
    query =
      from(membership in Membership,
        where: membership.user_id == ^user_id and membership.status == "active",
        join: account in assoc(membership, :account),
        where: account.type == "individual",
        preload: [account: account],
        order_by: [desc: membership.inserted_at, desc: membership.id],
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      membership -> {:ok, %{membership: membership, account: membership.account}}
    end
  end

  def access_state(%Account{subscription_status: "active"}, _now) do
    %{can_use_app: true, reason: nil}
  end

  def access_state(%Account{trial_ends_at: trial_ends_at}, now) do
    if DateTime.compare(now, trial_ends_at) == :lt do
      %{can_use_app: true, reason: nil}
    else
      %{can_use_app: false, reason: "trial_expired"}
    end
  end
end
