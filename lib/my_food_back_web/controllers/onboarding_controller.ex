defmodule MyFoodBackWeb.OnboardingController do
  use MyFoodBackWeb, :controller

  alias MyFoodBack.Accounts
  alias MyFoodBack.Repo
  alias MyFoodBack.Accounts.User

  def complete(conn, params) do
    user = Repo.get!(User, conn.assigns.current_session.user_id)

    case Accounts.complete_onboarding(user, params) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> render(:complete, result: result)

      {:error, %{code: "onboarding_already_complete"} = error} ->
        conn
        |> put_status(:conflict)
        |> render(:error, error: Map.put_new(error, :message, "Onboarding already complete"))

      {:error, %{code: "onboarding_invalid"} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: Map.put_new(error, :message, "Onboarding payload is invalid"))

      {:error, error} ->
        render_error(conn, error)
    end
  end

  defp render_error(conn, %{code: code} = error) do
    conn
    |> put_status(status_for(code))
    |> render(:error, error: Map.put_new(error, :message, message_for(code)))
  end

  defp render_error(conn, error) when is_atom(error) do
    render_error(conn, %{code: Atom.to_string(error)})
  end

  defp status_for("unauthenticated"), do: :unauthorized
  defp status_for("onboarding_already_complete"), do: :conflict
  defp status_for(_), do: :unprocessable_entity

  defp message_for(code) do
    code
    |> String.replace("_", " ")
    |> String.capitalize()
  end
end
