defmodule MyFoodBack.Auth.Session do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "sessions" do
    field(:device_id_hash, :string)
    field(:refresh_token_hash, :string)
    field(:last_used_at, :utc_datetime)
    field(:expires_at, :utc_datetime)
    field(:revoked_at, :utc_datetime)
    field(:revoked_reason, :string)
    field(:user_agent, :string)
    field(:ip_hash, :string)

    belongs_to(:user, MyFoodBack.Accounts.User)
    belongs_to(:rotated_from, __MODULE__)

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :device_id_hash,
      :refresh_token_hash,
      :last_used_at,
      :expires_at,
      :revoked_at,
      :revoked_reason,
      :user_agent,
      :ip_hash
    ])
    |> validate_required([:user_id, :refresh_token_hash, :expires_at])
    |> unique_constraint(:refresh_token_hash)
  end
end
