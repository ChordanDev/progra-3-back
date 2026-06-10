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

    # Setup endpoints: must remain available while the Account is in Access Lock
    # so locked Users can complete onboarding. These are NOT piped through
    # `RequireUnlockedAccount` — protected app data routes still are.
    post("/onboarding/complete", OnboardingController, :complete)
    get("/me/preferences", PreferencesController, :show)
    put("/me/preferences", PreferencesController, :update)
    get("/me/slot-cooking-times", SlotCookingTimesController, :show)
    put("/me/slot-cooking-times", SlotCookingTimesController, :update)
  end

  if Application.compile_env(:my_food_back, :dev_routes) do
    forward("/dev/mailbox", Plug.Swoosh.MailboxPreview)
  end
end
