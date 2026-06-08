defmodule MyFoodBack.Auth.Tokens do
  @access_token_max_age_seconds 900
  @refresh_token_bytes 32

  def access_token_max_age_seconds, do: @access_token_max_age_seconds

  def generate_refresh_token do
    @refresh_token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  def hash_refresh_token(token) when is_binary(token) do
    :crypto.mac(:hmac, :sha256, secret(), "refresh:#{token}")
    |> Base.encode16(case: :lower)
  end

  def hash_identifier(nil), do: nil
  def hash_identifier(""), do: nil

  def hash_identifier(value) when is_binary(value) do
    :crypto.mac(:hmac, :sha256, secret(), "identifier:#{value}")
    |> Base.encode16(case: :lower)
  end

  def sign_access_token(session, now) do
    payload = %{
      "session_id" => session.id,
      "user_id" => session.user_id,
      "exp" => DateTime.add(now, @access_token_max_age_seconds, :second) |> DateTime.to_unix()
    }

    Phoenix.Token.sign(MyFoodBackWeb.Endpoint, salt(), payload)
  end

  def verify_access_token(token, now) when is_binary(token) do
    with {:ok, %{"exp" => exp} = payload} <-
           Phoenix.Token.verify(MyFoodBackWeb.Endpoint, salt(), token, max_age: :infinity),
         true <- DateTime.to_unix(now) < exp do
      {:ok, payload}
    else
      false -> {:error, :access_token_expired}
      _ -> {:error, :access_token_invalid}
    end
  end

  def verify_access_token(_token, _now), do: {:error, :access_token_invalid}

  defp salt, do: "auth access token"

  defp secret do
    endpoint_config = Application.get_env(:my_food_back, MyFoodBackWeb.Endpoint, [])
    Keyword.fetch!(endpoint_config, :secret_key_base)
  end
end
