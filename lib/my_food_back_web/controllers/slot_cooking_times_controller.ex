defmodule MyFoodBackWeb.SlotCookingTimesController do
  use MyFoodBackWeb, :controller

  alias MyFoodBack.Accounts
  alias MyFoodBack.Accounts.User
  alias MyFoodBack.Repo

  def show(conn, _params) do
    user = Repo.get!(User, conn.assigns.current_session.user_id)

    case Accounts.get_slot_cooking_times(user) do
      {:ok, slots} ->
        conn
        |> put_status(:ok)
        |> render(:show, slots: slots)
    end
  end

  def update(conn, params) do
    user = Repo.get!(User, conn.assigns.current_session.user_id)

    case Accounts.update_slot_cooking_times(user, params) do
      {:ok, slots} ->
        conn
        |> put_status(:ok)
        |> render(:show, slots: slots)

      {:error, %{code: "slot_cooking_times_invalid"} = error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: Map.put_new(error, :message, "Slot cooking times are invalid"))

      {:error, error} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, error: Map.put_new(error, :message, "Slot cooking times are invalid"))
    end
  end
end
