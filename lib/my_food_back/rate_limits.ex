defmodule MyFoodBack.RateLimits do
  import Ecto.Query

  alias MyFoodBack.RateLimits.Event
  alias MyFoodBack.Repo

  @request_email_limit 3
  @request_email_window_minutes 15
  @request_ip_limit 20
  @request_ip_window_minutes 60
  @request_device_limit 10
  @request_device_window_minutes 60

  def check_request_code(email, flow, opts) do
    now = Keyword.fetch!(opts, :now)
    ip = Keyword.get(opts, :ip)
    device_id = Keyword.get(opts, :device_id)

    with :ok <-
           check_limit(
             :email,
             request_key("email", flow, email),
             "request_code",
             @request_email_limit,
             @request_email_window_minutes,
             now
           ),
         :ok <-
           check_optional_limit(
             :ip,
             ip,
             "request_code",
             @request_ip_limit,
             @request_ip_window_minutes,
             now
           ),
         :ok <-
           check_optional_limit(
             :device,
             device_id,
             "request_code",
             @request_device_limit,
             @request_device_window_minutes,
             now
           ) do
      :ok
    end
  end

  def record_request_code(email, flow, opts) do
    now = Keyword.fetch!(opts, :now)
    ip = Keyword.get(opts, :ip)
    device_id = Keyword.get(opts, :device_id)

    Repo.insert!(event_changeset(:email, request_key("email", flow, email), "request_code", now))

    if present?(ip) do
      Repo.insert!(event_changeset(:ip, ip, "request_code", now))
    end

    if present?(device_id) do
      Repo.insert!(event_changeset(:device, device_id, "request_code", now))
    end

    :ok
  end

  def hash_value(nil), do: nil
  def hash_value(value) when is_binary(value), do: hash(value)

  defp check_optional_limit(_scope, value, _action, _limit, _minutes, _now)
       when value in [nil, ""], do: :ok

  defp check_optional_limit(scope, value, action, limit, minutes, now) do
    check_limit(scope, value, action, limit, minutes, now)
  end

  defp check_limit(scope, raw_key, action, limit, minutes, now) do
    key_hash = hash(raw_key)
    since = DateTime.add(now, -minutes, :minute)

    count =
      Event
      |> where([event], event.key_hash == ^key_hash)
      |> where([event], event.scope == ^Atom.to_string(scope))
      |> where([event], event.action == ^action)
      |> where([event], event.occurred_at > ^since)
      |> Repo.aggregate(:count)

    if count >= limit, do: {:error, :rate_limited}, else: :ok
  end

  defp event_changeset(scope, raw_key, action, now) do
    Event.changeset(%Event{}, %{
      key_hash: hash(raw_key),
      scope: Atom.to_string(scope),
      action: action,
      occurred_at: now
    })
  end

  defp request_key(prefix, flow, email), do: "#{prefix}:#{flow}:#{email}"

  defp present?(value), do: is_binary(value) and value != ""

  defp hash(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
  end
end
