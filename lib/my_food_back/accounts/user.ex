defmodule MyFoodBack.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @cooking_skills ~w(beginner intermediate advanced)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field(:email, :string)
    field(:display_name, :string)
    field(:household_size, :integer)
    field(:cooking_skill, :string)
    field(:onboarding_completed_at, :utc_datetime)

    has_many(:memberships, MyFoodBack.Accounts.Membership)
    has_one(:preferences, MyFoodBack.Accounts.UserPreferences)
    has_many(:slot_cooking_times, MyFoodBack.Accounts.UserSlotCookingTime)

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

  def onboarding_profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :household_size, :cooking_skill])
    |> validate_required([:display_name, :household_size, :cooking_skill])
    |> validate_length(:display_name, min: 1, max: 60)
    |> validate_number(:household_size, greater_than_or_equal_to: 1, less_than_or_equal_to: 20)
    |> validate_inclusion(:cooking_skill, @cooking_skills)
  end

  def completion_changeset(user, attrs) do
    user
    |> cast(attrs, [:onboarding_completed_at])
    |> validate_required([:onboarding_completed_at])
  end
end
