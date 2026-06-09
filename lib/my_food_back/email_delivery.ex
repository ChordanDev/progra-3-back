defmodule MyFoodBack.EmailDelivery do
  import Swoosh.Email

  alias MyFoodBack.Mailer

  def deliver_code(email, code, flow) when flow in [:signup, :login] do
    subject = subject_for(flow)

    new()
    |> to(email)
    |> from(from_address())
    |> subject(subject)
    |> text_body("Your access code is #{code}. It expires in 10 minutes.")
    |> Mailer.deliver()
    |> case do
      {:ok, _metadata} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp subject_for(:signup), do: "Your account creation code"
  defp subject_for(:login), do: "Your sign-in code"

  defp from_address do
    config = Application.fetch_env!(:my_food_back, :email_delivery)

    {Keyword.fetch!(config, :from_name), Keyword.fetch!(config, :from_address)}
  end
end
