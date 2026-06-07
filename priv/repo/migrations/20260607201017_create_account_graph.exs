defmodule MyFoodBack.Repo.Migrations.CreateAccountGraph do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :display_name, :string
      add :onboarding_completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :trial_started_at, :utc_datetime, null: false
      add :trial_ends_at, :utc_datetime, null: false
      add :subscription_status, :string, null: false, default: "none"

      timestamps(type: :utc_datetime)
    end

    create table(:memberships, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :string, null: false
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create index(:memberships, [:account_id])
    create unique_index(:memberships, [:user_id, :account_id])
  end
end
