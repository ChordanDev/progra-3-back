defmodule MyFoodBack.Repo do
  use Ecto.Repo,
    otp_app: :my_food_back,
    adapter: Ecto.Adapters.Postgres
end
