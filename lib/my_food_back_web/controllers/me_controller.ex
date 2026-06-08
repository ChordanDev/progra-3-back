defmodule MyFoodBackWeb.MeController do
  use MyFoodBackWeb, :controller

  alias MyFoodBack.Auth

  def show(conn, _params) do
    conn.assigns.current_session
    |> Auth.current_user_snapshot()
    |> case do
      {:ok, me} -> render(conn, :show, me: me)
      {:error, error} -> render_error(conn, error)
    end
  end

  defp render_error(conn, %{code: code} = error) do
    conn
    |> put_status(status_for(code))
    |> render(:error, error: Map.put_new(error, :message, message_for(code)))
  end

  defp status_for("unauthenticated"), do: :unauthorized
  defp status_for(_code), do: :unprocessable_entity

  defp message_for(code) do
    code
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
