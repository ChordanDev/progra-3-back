defmodule MyFoodBackWeb.PageController do
  use MyFoodBackWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
