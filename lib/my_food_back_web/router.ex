defmodule MyFoodBackWeb.Router do
  use MyFoodBackWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", MyFoodBackWeb do
    pipe_through(:api)
  end
end
