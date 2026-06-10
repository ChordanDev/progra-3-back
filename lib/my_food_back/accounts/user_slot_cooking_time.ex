defmodule MyFoodBack.Accounts.UserSlotCookingTime do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @supported_slots ~w(breakfast lunch dinner)
  @hunger_levels ~w(light normal strong)

  schema "user_slot_cooking_times" do
    belongs_to :user, MyFoodBack.Accounts.User

    field :meal_slot, :string
    field :cooking_time_minutes, :integer
    field :hunger_level, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:meal_slot, :cooking_time_minutes, :hunger_level])
    |> validate_required([:meal_slot, :cooking_time_minutes, :hunger_level])
    |> validate_inclusion(:meal_slot, @supported_slots)
    |> validate_inclusion(:hunger_level, @hunger_levels)
    |> validate_number(:cooking_time_minutes, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :meal_slot])
  end
end
