defmodule MyFoodBackWeb.Plugs.AuthenticateSession do
  import Plug.Conn
  import Phoenix.Controller

  alias MyFoodBack.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> bearer_token()
    |> Auth.verify_access_token()
    |> case do
      {:ok, session} -> assign(conn, :current_session, session)
      {:error, error} -> halt_unauthenticated(conn, error)
    end
  end

  defp bearer_token(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> case do
      "Bearer " <> token -> token
      _other -> nil
    end
  end

  defp halt_unauthenticated(conn, %{code: code}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: MyFoodBackWeb.AuthJSON)
    |> render(:error, error: %{code: code, message: message_for(code)})
    |> halt()
  end

  defp message_for(code) do
    code
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
