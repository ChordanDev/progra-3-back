defmodule MyFoodBack.Auth.EmailCode do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "email_codes" do
    field(:email, :string)
    field(:flow, :string)
    field(:code_hash, :string)
    field(:expires_at, :utc_datetime)
    field(:attempt_count, :integer, default: 0)
    field(:consumed_at, :utc_datetime)
    field(:invalidated_at, :utc_datetime)
    field(:last_sent_at, :utc_datetime)
    field(:request_ip_hash, :string)
    field(:device_id_hash, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(email_code, attrs) do
    email_code
    |> cast(attrs, [
      :email,
      :flow,
      :code_hash,
      :expires_at,
      :attempt_count,
      :consumed_at,
      :invalidated_at,
      :last_sent_at,
      :request_ip_hash,
      :device_id_hash
    ])
    |> validate_required([:email, :flow, :code_hash, :expires_at, :last_sent_at])
    |> validate_inclusion(:flow, ["signup", "login"])
  end
end
