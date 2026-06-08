defmodule MyFoodBack.Auth do
  import Ecto.Query

  alias Ecto.Multi
  alias MyFoodBack.Accounts
  alias MyFoodBack.Accounts.{Account, Membership, User}
  alias MyFoodBack.Auth.{EmailCode, Session, Tokens}
  alias MyFoodBack.{EmailDelivery, RateLimits, Repo}

  @code_ttl_seconds 600
  @resend_cooldown_seconds 60
  @max_attempts 5
  @refresh_token_ttl_seconds 30 * 24 * 60 * 60

  def request_signup_code(attrs, opts \\ []) do
    email = normalize_email(attrs)

    with :ok <- validate_email(email),
         :ok <- ensure_user_missing(email),
         :ok <- request_code(:signup, email, opts) do
      {:ok, code_sent_response()}
    end
  end

  def request_login_code(attrs, opts \\ []) do
    email = normalize_email(attrs)

    with :ok <- validate_email(email),
         :ok <- ensure_user_exists(email),
         :ok <- request_code(:login, email, opts) do
      {:ok, code_sent_response()}
    end
  end

  def verify_signup_code(attrs, opts \\ []), do: verify_code(:signup, attrs, opts)
  def verify_login_code(attrs, opts \\ []), do: verify_code(:login, attrs, opts)

  def refresh_session(refresh_token, opts \\ [])

  def refresh_session(refresh_token, opts) when is_binary(refresh_token) do
    now = now(opts)
    token_hash = Tokens.hash_refresh_token(refresh_token)

    case Repo.get_by(Session, refresh_token_hash: token_hash) do
      nil ->
        detect_replayed_refresh(token_hash)

      %Session{revoked_at: revoked_at, revoked_reason: "rotated"} when not is_nil(revoked_at) ->
        error(:refresh_token_replayed)

      %Session{revoked_at: revoked_at} when not is_nil(revoked_at) ->
        error(:refresh_token_revoked)

      %Session{} = session ->
        if DateTime.compare(now, session.expires_at) == :lt do
          rotate_session(session, opts, now)
        else
          error(:refresh_token_expired)
        end
    end
  end

  def refresh_session(_refresh_token, _opts), do: error(:refresh_token_invalid)

  def logout(refresh_token, opts \\ [])

  def logout(refresh_token, opts) when is_binary(refresh_token) do
    now = now(opts)
    token_hash = Tokens.hash_refresh_token(refresh_token)

    case Repo.get_by(Session, refresh_token_hash: token_hash) do
      nil ->
        error(:refresh_token_invalid)

      %Session{revoked_at: revoked_at, revoked_reason: "rotated"} when not is_nil(revoked_at) ->
        error(:refresh_token_replayed)

      %Session{revoked_at: revoked_at} when not is_nil(revoked_at) ->
        :ok

      %Session{} = session ->
        session
        |> Session.changeset(%{revoked_at: now, revoked_reason: "logout"})
        |> Repo.update()
        |> case do
          {:ok, _session} -> :ok
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  def logout(_refresh_token, _opts), do: error(:refresh_token_invalid)

  def logout_current_session(refresh_token, current_session, opts \\ [])

  def logout_current_session(refresh_token, %Session{} = current_session, opts) do
    if Tokens.hash_refresh_token(refresh_token) == current_session.refresh_token_hash do
      logout(refresh_token, opts)
    else
      error(:refresh_token_session_mismatch)
    end
  end

  def logout_current_session(_refresh_token, _current_session, _opts),
    do: error(:refresh_token_invalid)

  def verify_access_token(access_token, opts \\ []) do
    now = now(opts)

    with {:ok, %{"session_id" => session_id}} <- Tokens.verify_access_token(access_token, now),
         %Session{revoked_at: nil} = session <- Repo.get(Session, session_id),
         true <- DateTime.compare(now, session.expires_at) == :lt do
      {:ok, session}
    else
      {:error, :access_token_expired} -> error(:access_token_expired)
      false -> error(:access_token_expired)
      _ -> error(:unauthenticated)
    end
  end

  def current_user_snapshot(%Session{user_id: user_id}, opts \\ []) do
    now = now(opts)

    with %User{} = user <- Repo.get(User, user_id),
         {:ok, %{account: account, membership: membership}} <- Accounts.get_current_account(user) do
      {:ok, current_snapshot(user, account, membership, now)}
    else
      nil -> error(:unauthenticated)
      {:error, :not_found} -> error(:account_not_found)
    end
  end

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
          with :ok <-
                 map_rate_limit_record(
                   RateLimits.record_request_code(email, Atom.to_string(flow), opts)
                 ) do
            EmailDelivery.deliver_code(email, code, flow)
          end

        {:error, _step, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  defp verify_code(flow, attrs, opts) do
    email = normalize_email(attrs)
    code = Map.get(attrs, :code) || Map.get(attrs, "code")
    now = now(opts)

    with :ok <- validate_email(email),
         :ok <- validate_code_format(code),
         {:ok, email_code} <- latest_active_code(email, flow),
         :ok <- verify_loaded_code(email_code, flow, email, code, now) do
      complete_verified_code(flow, email_code, attrs, opts, now)
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

  defp complete_verified_code(:signup, email_code, attrs, opts, now) do
    email = email_code.email
    device_id = Map.get(attrs, :device_id) || Map.get(attrs, "device_id")

    result =
      Multi.new()
      |> Multi.update_all(:email_code, consumable_code_query(email_code.id),
        set: [consumed_at: now]
      )
      |> Multi.run(:ensure_email_code_consumed, &ensure_email_code_consumed/2)
      |> Multi.merge(fn _changes ->
        Accounts.create_individual_account_multi(%{email: email}, now: now)
      end)
      |> Multi.run(:auth, fn repo, %{user: user, account: account, membership: membership} ->
        {:ok, build_auth_response(repo, user, account, membership, device_id, opts, now)}
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{auth: auth}} -> {:ok, auth}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp complete_verified_code(:login, email_code, attrs, opts, now) do
    email = email_code.email
    device_id = Map.get(attrs, :device_id) || Map.get(attrs, "device_id")

    with %User{} = user <- Repo.get_by(User, email: email),
         {:ok, %{account: account, membership: membership}} <- Accounts.get_current_account(user) do
      result =
        Multi.new()
        |> Multi.update_all(:email_code, consumable_code_query(email_code.id),
          set: [consumed_at: now]
        )
        |> Multi.run(:ensure_email_code_consumed, &ensure_email_code_consumed/2)
        |> Multi.run(:auth, fn repo, _changes ->
          {:ok, build_auth_response(repo, user, account, membership, device_id, opts, now)}
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{auth: auth}} -> {:ok, auth}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      nil -> error(:email_not_found)
      {:error, :not_found} -> error(:account_not_found)
    end
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

  defp validate_email(email) when is_binary(email) do
    if email =~ ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/, do: :ok, else: error(:invalid_email)
  end

  defp validate_email(_email), do: error(:invalid_email)

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

  defp build_auth_response(repo, user, account, membership, device_id, opts, now) do
    refresh_token = Tokens.generate_refresh_token()

    session =
      %Session{user_id: user.id}
      |> Session.changeset(%{
        device_id_hash: Tokens.hash_identifier(device_id),
        refresh_token_hash: Tokens.hash_refresh_token(refresh_token),
        expires_at: DateTime.add(now, @refresh_token_ttl_seconds, :second),
        last_used_at: now,
        user_agent: normalize_user_agent(Keyword.get(opts, :user_agent)),
        ip_hash: Tokens.hash_identifier(Keyword.get(opts, :ip))
      })
      |> repo.insert!()

    auth_response(user, account, membership, session, refresh_token, now)
  end

  defp rotate_session(%Session{} = old_session, opts, now) do
    refresh_token = Tokens.generate_refresh_token()

    result =
      Multi.new()
      |> Multi.update_all(:revoke_old, active_session_query(old_session.id),
        set: [revoked_at: now, revoked_reason: "rotated", last_used_at: now]
      )
      |> Multi.run(:ensure_old_revoked, &ensure_old_revoked/2)
      |> Multi.insert(:session, fn _changes ->
        %Session{user_id: old_session.user_id, rotated_from_id: old_session.id}
        |> Session.changeset(%{
          device_id_hash: old_session.device_id_hash,
          refresh_token_hash: Tokens.hash_refresh_token(refresh_token),
          expires_at: DateTime.add(now, @refresh_token_ttl_seconds, :second),
          last_used_at: now,
          user_agent:
            normalize_user_agent(Keyword.get(opts, :user_agent, old_session.user_agent)),
          ip_hash: Tokens.hash_identifier(Keyword.get(opts, :ip)) || old_session.ip_hash
        })
      end)
      |> Repo.transaction()

    case result do
      {:ok, %{session: session}} -> {:ok, token_response(session, refresh_token, now)}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp detect_replayed_refresh(token_hash) do
    if Repo.exists?(
         from(session in Session,
           where:
             session.rotated_from_id in subquery(
               from(old in Session, where: old.refresh_token_hash == ^token_hash, select: old.id)
             )
         )
       ) do
      error(:refresh_token_replayed)
    else
      error(:refresh_token_invalid)
    end
  end

  defp active_session_query(session_id) do
    from(session in Session,
      where: session.id == ^session_id,
      where: is_nil(session.revoked_at)
    )
  end

  defp consumable_code_query(email_code_id) do
    from(code in EmailCode,
      where: code.id == ^email_code_id,
      where: is_nil(code.consumed_at),
      where: is_nil(code.invalidated_at)
    )
  end

  defp ensure_email_code_consumed(_repo, %{email_code: {1, _rows}}), do: {:ok, :consumed}
  defp ensure_email_code_consumed(_repo, _changes), do: error(:code_invalid)

  defp ensure_old_revoked(_repo, %{revoke_old: {1, _rows}}), do: {:ok, :revoked}
  defp ensure_old_revoked(_repo, _changes), do: error(:refresh_token_replayed)

  defp normalize_user_agent(nil), do: nil

  defp normalize_user_agent(user_agent) when is_binary(user_agent) do
    String.slice(user_agent, 0, 255)
  end

  defp normalize_user_agent(_user_agent), do: nil

  defp auth_response(user, account, membership, session, refresh_token, now) do
    %{
      access_token: Tokens.sign_access_token(session, now),
      refresh_token: refresh_token,
      token_type: "Bearer",
      me: current_snapshot(user, account, membership, now)
    }
  end

  defp token_response(session, refresh_token, now) do
    %{
      access_token: Tokens.sign_access_token(session, now),
      refresh_token: refresh_token,
      token_type: "Bearer"
    }
  end

  defp current_snapshot(%User{} = user, %Account{} = account, %Membership{} = membership, now) do
    %{
      user: %{id: user.id, email: user.email, display_name: user.display_name},
      account: %{
        id: account.id,
        type: account.type,
        trial_ends_at: account.trial_ends_at,
        subscription_status: account.subscription_status,
        access: Accounts.access_state(account, now)
      },
      membership: %{role: membership.role},
      onboarding: %{is_complete: not is_nil(user.onboarding_completed_at)}
    }
  end

  defp map_rate_limit(:ok), do: :ok
  defp map_rate_limit({:error, :rate_limited}), do: error(:rate_limited)

  defp map_rate_limit_record(:ok), do: :ok
  defp map_rate_limit_record({:error, _reason}), do: error(:rate_limit_record_failed)

  defp error(code), do: {:error, %{code: Atom.to_string(code)}}
end
