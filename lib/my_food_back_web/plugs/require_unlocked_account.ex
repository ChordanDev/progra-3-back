defmodule MyFoodBackWeb.Plugs.RequireUnlockedAccount do
  import Plug.Conn
  import Phoenix.Controller

  alias MyFoodBack.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    case Auth.current_user_snapshot(conn.assigns.current_session) do
      {:ok, %{account: %{access: %{can_use_app: true}}} = me} -> assign(conn, :current_me, me)
      {:ok, %{account: %{access: %{reason: reason}}}} -> halt_locked(conn, reason)
      {:error, error} -> halt_locked(conn, error.code)
    end
  end

  defp halt_locked(conn, reason) do
    conn
    |> put_status(:payment_required)
    |> put_view(json: MyFoodBackWeb.AuthJSON)
    |> render(:error, error: %{code: "account_locked", message: "Account locked", reason: reason})
    |> halt()
  end
end
