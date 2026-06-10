defmodule MyFoodBackWeb.PreferencesController do
  use MyFoodBackWeb, :controller

  alias MyFoodBack.Accounts
  alias MyFoodBack.Accounts.User
  alias MyFoodBack.Repo

  def show(conn, _params) do
    user = Repo.get!(User, conn.assigns.current_session.user_id)

    case Accounts.get_user_preferences(user) do
      {:ok, nil} ->
        conn
        |> put_status(:ok)
        |> render(:show, preferences: empty_preferences())

      {:ok, prefs} ->
        conn
        |> put_status(:ok)
        |> render(:show, preferences: prefs)
    end
  end

  def update(conn, params) do
    user = Repo.get!(User, conn.assigns.current_session.user_id)

    case Accounts.update_user_preferences(user, params) do
      {:ok, prefs} ->
        conn
        |> put_status(:ok)
        |> render(:show, preferences: prefs)

      {:error, %{code: "preferences_invalid"} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: Map.put_new(error, :message, "Preferences are invalid"))

      {:error, error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: Map.put_new(error, :message, "Preferences are invalid"))
    end
  end

  defp empty_preferences do
    %{diet: nil, hard_restrictions: [], soft_preferences: []}
  end
end
