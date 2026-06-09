defmodule MyFoodBack.Repo.Migrations.EnforceLowercaseUserEmailIndex do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:users, [:email])

    create unique_index(:users, ["lower(email)"], name: :users_email_index)
  end
end
