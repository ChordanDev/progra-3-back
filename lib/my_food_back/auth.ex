defmodule MyFoodBack.Auth do
  import Ecto.Query

  alias Ecto.Multi
  alias MyFoodBack.Accounts
  alias MyFoodBack.Accounts.User
  alias MyFoodBack.Auth.EmailCode
  alias MyFoodBack.{EmailDelivery, RateLimits, Repo}

  @code_ttl_seconds 600
  @resend_cooldown_seconds 60
  @max_attempts 5

  def request_signup_code(attrs, opts \\ []) do
    email = normalize_email(attrs)

    with :ok <- ensure_user_missing(email),
         :ok <- request_code(:signup, email, opts) do
      {:ok, code_sent_response()}
    end
  end

  def request_login_code(attrs, opts \\ []) do
    email = normalize_email(attrs)

    with :ok <- ensure_user_exists(email),
         :ok <- request_code(:login, email, opts) do
      {:ok, code_sent_response()}
    end
  end

  def verify_signup_code(attrs, opts \\ []), do: verify_code(:signup, attrs, opts)
  def verify_login_code(attrs, opts \\ []), do: verify_code(:login, attrs, opts)

  defp request_code(flow, email, opts) do
    now = now(opts)
    opts = Keyword.put(opts, :now, now)

    with :ok <- check_cooldown(email, flow, now),
         :ok <- map_rate_limit(RateLimits.check_request_code(email, Atom.to_string(flow), opts)) do
      code = generate_code()
      code_hash = hash_code(flow, email, code)
      expires_at = DateTime.add(now, @code_ttl_seconds, :second)

      result =
        Multi.new()
        |> Multi.update_all(:invalidate_previous, active_codes_query(email, flow),
          set: [invalidated_at: now]
        )
        |> Multi.insert(
          :email_code,
          EmailCode.changeset(%EmailCode{}, %{
            email: email,
            flow: Atom.to_string(flow),
            code_hash: code_hash,
            expires_at: expires_at,
            last_sent_at: now,
            request_ip_hash: RateLimits.hash_value(Keyword.get(opts, :ip)),
            device_id_hash: RateLimits.hash_value(Keyword.get(opts, :device_id))
          })
        )
        |> Repo.transaction()

      case result do
        {:ok, _changes} ->
          RateLimits.record_request_code(email, Atom.to_string(flow), opts)
          EmailDelivery.deliver_code(email, code, flow)

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  defp verify_code(flow, attrs, opts) do
    email = normalize_email(attrs)
    code = Map.get(attrs, :code) || Map.get(attrs, "code")
    now = now(opts)

    with :ok <- validate_code_format(code),
         {:ok, email_code} <- latest_active_code(email, flow),
         :ok <- verify_loaded_code(email_code, flow, email, code, now) do
      email_code
      |> EmailCode.changeset(%{consumed_at: now})
      |> Repo.update()
    end
  end

  defp verify_loaded_code(%EmailCode{attempt_count: attempts}, _flow, _email, _code, _now)
       when attempts >= @max_attempts do
    error(:too_many_attempts)
  end

  defp verify_loaded_code(%EmailCode{} = email_code, flow, email, code, now) do
    cond do
      DateTime.compare(now, email_code.expires_at) != :lt ->
        error(:code_expired)

      secure_compare(email_code.code_hash, hash_code(flow, email, code)) ->
        :ok

      true ->
        email_code
        |> EmailCode.changeset(%{attempt_count: email_code.attempt_count + 1})
        |> Repo.update!()

        error(:code_invalid)
    end
  end

  defp check_cooldown(email, flow, now) do
    latest =
      EmailCode
      |> where([code], code.email == ^email and code.flow == ^Atom.to_string(flow))
      |> order_by([code], desc: code.last_sent_at)
      |> limit(1)
      |> Repo.one()

    case latest do
      nil ->
        :ok

      %EmailCode{last_sent_at: sent_at} ->
        if DateTime.diff(now, sent_at, :second) >= @resend_cooldown_seconds do
          :ok
        else
          error(:rate_limited)
        end
    end
  end

  defp latest_active_code(email, flow) do
    email
    |> active_codes_query(flow)
    |> order_by([code], desc: code.inserted_at, desc: code.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> error(:code_invalid)
      email_code -> {:ok, email_code}
    end
  end

  defp active_codes_query(email, flow) do
    from(code in EmailCode,
      where: code.email == ^email,
      where: code.flow == ^Atom.to_string(flow),
      where: is_nil(code.consumed_at),
      where: is_nil(code.invalidated_at)
    )
  end

  defp ensure_user_missing(email) do
    if Repo.exists?(from(user in User, where: user.email == ^email)) do
      error(:email_already_exists)
    else
      :ok
    end
  end

  defp ensure_user_exists(email) do
    if Repo.exists?(from(user in User, where: user.email == ^email)) do
      :ok
    else
      error(:email_not_found)
    end
  end

  defp validate_code_format(code) when is_binary(code) do
    if code =~ ~r/^\d{6}$/, do: :ok, else: error(:code_invalid)
  end

  defp validate_code_format(_code), do: error(:code_invalid)

  defp normalize_email(attrs) do
    attrs
    |> Map.get(:email, Map.get(attrs, "email"))
    |> Accounts.normalize_email()
  end

  defp generate_code do
    :crypto.strong_rand_bytes(4)
    |> :binary.decode_unsigned()
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(6, "0")
  end

  defp hash_code(flow, email, code) do
    :crypto.mac(:hmac, :sha256, secret(), "#{flow}:#{email}:#{code}")
    |> Base.encode16(case: :lower)
  end

  defp secure_compare(left, right) do
    byte_size(left) == byte_size(right) and Plug.Crypto.secure_compare(left, right)
  end

  defp secret do
    endpoint_config = Application.get_env(:my_food_back, MyFoodBackWeb.Endpoint, [])
    Keyword.fetch!(endpoint_config, :secret_key_base)
  end

  defp now(opts), do: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

  defp code_sent_response do
    %{
      status: "code_sent",
      expires_in_seconds: @code_ttl_seconds,
      resend_available_in_seconds: @resend_cooldown_seconds
    }
  end

  defp map_rate_limit(:ok), do: :ok
  defp map_rate_limit({:error, :rate_limited}), do: error(:rate_limited)

  defp error(code), do: {:error, %{code: Atom.to_string(code)}}
end
