defmodule MyFoodBack.RateLimits.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "rate_limit_events" do
    field(:key_hash, :string)
    field(:scope, :string)
    field(:action, :string)
    field(:occurred_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:key_hash, :scope, :action, :occurred_at])
    |> validate_required([:key_hash, :scope, :action, :occurred_at])
    |> validate_inclusion(:scope, ["email", "ip", "device"])
    |> validate_inclusion(:action, ["request_code", "verify_code"])
  end
end
