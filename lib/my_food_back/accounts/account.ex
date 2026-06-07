defmodule MyFoodBack.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "accounts" do
    field(:type, :string, default: "individual")
    field(:trial_started_at, :utc_datetime)
    field(:trial_ends_at, :utc_datetime)
    field(:subscription_status, :string, default: "none")

    has_many(:memberships, MyFoodBack.Accounts.Membership)

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:type, :trial_started_at, :trial_ends_at, :subscription_status])
    |> validate_required([:type, :trial_started_at, :trial_ends_at, :subscription_status])
    |> validate_inclusion(:type, ["individual", "family", "family_plus"])
    |> validate_inclusion(:subscription_status, ["none", "active", "past_due", "canceled"])
  end
end
