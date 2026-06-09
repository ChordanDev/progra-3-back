defmodule MyFoodBackWeb.Router do
  use MyFoodBackWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :authenticated_api do
    plug(MyFoodBackWeb.Plugs.AuthenticateSession)
  end

  scope "/api", MyFoodBackWeb do
    pipe_through(:api)

    post("/auth/signup/request-code", AuthController, :signup_request_code)
    post("/auth/signup/verify-code", AuthController, :signup_verify_code)
    post("/auth/login/request-code", AuthController, :login_request_code)
    post("/auth/login/verify-code", AuthController, :login_verify_code)
    post("/auth/refresh", AuthController, :refresh)

    pipe_through(:authenticated_api)

    post("/auth/logout", AuthController, :logout)
    get("/me", MeController, :show)
  end

  if Application.compile_env(:my_food_back, :dev_routes) do
    forward("/dev/mailbox", Plug.Swoosh.MailboxPreview)
  end
end
