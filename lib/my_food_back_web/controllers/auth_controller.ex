defmodule MyFoodBackWeb.AuthController do
  use MyFoodBackWeb, :controller

  alias MyFoodBack.Auth

  def signup_request_code(conn, params) do
    params
    |> Auth.request_signup_code(request_opts(conn))
    |> respond(conn, :code_sent)
  end

  def signup_verify_code(conn, params) do
    params
    |> normalize_device_id()
    |> Auth.verify_signup_code(request_opts(conn))
    |> respond(conn, :auth)
  end

  def login_request_code(conn, params) do
    params
    |> Auth.request_login_code(request_opts(conn))
    |> respond(conn, :code_sent)
  end

  def login_verify_code(conn, params) do
    params
    |> normalize_device_id()
    |> Auth.verify_login_code(request_opts(conn))
    |> respond(conn, :auth)
  end

  def refresh(conn, params) do
    params
    |> get_param("refreshToken")
    |> Auth.refresh_session(request_opts(conn))
    |> respond(conn, :token)
  end

  def logout(conn, params) do
    refresh_token = get_param(params, "refreshToken")

    case Auth.logout_current_session(
           refresh_token,
           conn.assigns.current_session,
           request_opts(conn)
         ) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, error} -> render_error(conn, error)
    end
  end

  defp respond({:ok, response}, conn, :code_sent),
    do: render(conn, :code_sent, response: response)

  defp respond({:ok, auth}, conn, :auth), do: render(conn, :auth, auth: auth)
  defp respond({:ok, token}, conn, :token), do: render(conn, :token, token: token)
  defp respond({:error, error}, conn, _template), do: render_error(conn, error)

  defp render_error(conn, %{code: code} = error) do
    conn
    |> put_status(status_for(code))
    |> render(:error, error: Map.put_new(error, :message, message_for(code)))
  end

  defp status_for("email_already_exists"), do: :conflict
  defp status_for("email_not_found"), do: :not_found
  defp status_for("rate_limited"), do: :too_many_requests
  defp status_for("unauthenticated"), do: :unauthorized
  defp status_for("access_token_expired"), do: :unauthorized
  defp status_for("refresh_token_invalid"), do: :unauthorized
  defp status_for("refresh_token_revoked"), do: :unauthorized
  defp status_for("refresh_token_replayed"), do: :unauthorized
  defp status_for("refresh_token_expired"), do: :unauthorized
  defp status_for("refresh_token_session_mismatch"), do: :unauthorized
  defp status_for("invalid_email"), do: :unprocessable_entity
  defp status_for("code_invalid"), do: :unprocessable_entity
  defp status_for("code_expired"), do: :unprocessable_entity
  defp status_for("too_many_attempts"), do: :unprocessable_entity
  defp status_for(_code), do: :unprocessable_entity

  defp message_for(code) do
    code
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp request_opts(conn) do
    [
      ip: remote_ip(conn),
      user_agent: conn |> get_req_header("user-agent") |> List.first()
    ]
  end

  defp remote_ip(%Plug.Conn{remote_ip: remote_ip}) when is_tuple(remote_ip) do
    remote_ip
    |> :inet.ntoa()
    |> to_string()
  end

  defp remote_ip(_conn), do: nil

  defp normalize_device_id(params) do
    case get_param(params, "deviceId") do
      nil -> params
      device_id -> Map.put(params, "device_id", device_id)
    end
  end

  defp get_param(params, key),
    do: Map.get(params, key) || Map.get(params, Phoenix.Naming.underscore(key))
end
