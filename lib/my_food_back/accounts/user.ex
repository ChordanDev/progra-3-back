defmodule MyFoodBack.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field(:email, :string)
    field(:display_name, :string)
    field(:onboarding_completed_at, :utc_datetime)

    has_many(:memberships, MyFoodBack.Accounts.Membership)

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :display_name, :onboarding_completed_at])
    |> update_change(:email, &MyFoodBack.Accounts.normalize_email/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    |> unique_constraint(:email)
  end
end
