defmodule MyFoodBack.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :device_id_hash, :string
      add :refresh_token_hash, :string, null: false
      add :rotated_from_id, references(:sessions, type: :binary_id, on_delete: :nilify_all)
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime, null: false
      add :revoked_at, :utc_datetime
      add :revoked_reason, :string
      add :user_agent, :string
      add :ip_hash, :string

      timestamps(type: :utc_datetime)
    end

    create index(:sessions, [:user_id])
    create unique_index(:sessions, [:refresh_token_hash])
    create index(:sessions, [:rotated_from_id])
  end
end
