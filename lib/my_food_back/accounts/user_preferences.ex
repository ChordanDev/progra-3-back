defmodule MyFoodBack.Accounts.UserPreferences do
  use Ecto.Schema
  import Ecto.Changeset

  alias MyFoodBack.Accounts.Catalog

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_preferences" do
    belongs_to :user, MyFoodBack.Accounts.User

    field :diet, :string
    field :hard_restrictions, {:array, :string}, default: []
    field :soft_preferences, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  def changeset(preferences, attrs) do
    preferences
    |> cast(attrs, [:diet, :hard_restrictions, :soft_preferences])
    |> validate_diet()
    |> validate_hard_restrictions()
    |> unique_constraint(:user_id)
  end

  defp validate_diet(changeset) do
    case get_field(changeset, :diet) do
      nil ->
        changeset

      code ->
        if Catalog.valid_diet?(code) do
          changeset
        else
          add_error(changeset, :diet, "is not in the configured catalog")
        end
    end
  end

  defp validate_hard_restrictions(changeset) do
    case get_field(changeset, :hard_restrictions) do
      nil ->
        changeset

      codes ->
        invalid = Enum.reject(codes, &Catalog.valid_hard_restriction?/1)

        if invalid == [] do
          changeset
        else
          add_error(
            changeset,
            :hard_restrictions,
            "contains codes not in the configured catalog: #{Enum.join(invalid, ",")}"
          )
        end
    end
  end
end
