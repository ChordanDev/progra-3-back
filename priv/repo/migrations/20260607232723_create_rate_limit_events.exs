defmodule MyFoodBack.Repo.Migrations.CreateRateLimitEvents do
  use Ecto.Migration

  def change do
    create table(:rate_limit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key_hash, :string, null: false
      add :scope, :string, null: false
      add :action, :string, null: false
      add :occurred_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:rate_limit_events, [:key_hash, :scope, :action, :occurred_at])
  end
end
