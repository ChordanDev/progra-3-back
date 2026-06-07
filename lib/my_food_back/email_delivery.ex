defmodule MyFoodBack.EmailDelivery do
  import Swoosh.Email

  alias MyFoodBack.Mailer

  def deliver_code(email, code, flow) when flow in [:signup, :login] do
    subject = subject_for(flow)

    new()
    |> to(email)
    |> from({"Meal Planner", "no-reply@example.com"})
    |> subject(subject)
    |> text_body("Tu código de acceso es #{code}. Expira en 10 minutos.")
    |> Mailer.deliver()
    |> case do
      {:ok, _metadata} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp subject_for(:signup), do: "Tu código para crear cuenta"
  defp subject_for(:login), do: "Tu código para iniciar sesión"
end
