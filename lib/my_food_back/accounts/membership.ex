defmodule MyFoodBack.Accounts.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "memberships" do
    field(:role, :string, default: "owner")
    field(:status, :string, default: "active")

    belongs_to(:user, MyFoodBack.Accounts.User)
    belongs_to(:account, MyFoodBack.Accounts.Account)

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :status])
    |> validate_required([:user_id, :account_id, :role, :status])
    |> validate_inclusion(:role, ["owner"])
    |> validate_inclusion(:status, ["active"])
    |> unique_constraint([:user_id, :account_id])
  end
end
