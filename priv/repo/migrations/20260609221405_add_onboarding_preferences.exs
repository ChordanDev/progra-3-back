defmodule MyFoodBack.Repo.Migrations.AddOnboardingPreferences do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :household_size, :integer
      add :cooking_skill, :string
    end

    create table(:user_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :diet, :string
      add :hard_restrictions, {:array, :string}, null: false, default: []
      add :soft_preferences, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_preferences, [:user_id])

    create table(:user_slot_cooking_times, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :meal_slot, :string, null: false
      add :cooking_time_minutes, :integer, null: false
      add :hunger_level, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_slot_cooking_times, [:user_id, :meal_slot])
  end

  def down do
    drop table(:user_slot_cooking_times)
    drop table(:user_preferences)

    alter table(:users) do
      remove :cooking_skill
      remove :household_size
    end
  end
end
