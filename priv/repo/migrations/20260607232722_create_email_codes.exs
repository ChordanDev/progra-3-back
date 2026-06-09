defmodule MyFoodBack.Repo.Migrations.CreateEmailCodes do
  use Ecto.Migration

  def change do
    create table(:email_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :flow, :string, null: false
      add :code_hash, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :consumed_at, :utc_datetime
      add :invalidated_at, :utc_datetime
      add :last_sent_at, :utc_datetime, null: false
      add :request_ip_hash, :string
      add :device_id_hash, :string

      timestamps(type: :utc_datetime)
    end

    create index(:email_codes, [:email, :flow])
    create index(:email_codes, [:email, :flow, :invalidated_at, :consumed_at])
  end
end
