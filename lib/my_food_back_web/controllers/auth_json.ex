defmodule MyFoodBackWeb.AuthJSON do
  def code_sent(%{response: response}), do: camelize(response)
  def auth(%{auth: auth}), do: camelize(auth)
  def token(%{token: token}), do: camelize(token)
  def error(%{error: error}), do: %{error: camelize(error)}

  def camelize(%DateTime{} = value), do: DateTime.to_iso8601(value)

  def camelize(value) when is_map(value) do
    Map.new(value, fn {key, val} -> {camel_key(key), camelize(val)} end)
  end

  def camelize(value) when is_list(value), do: Enum.map(value, &camelize/1)
  def camelize(value), do: value

  defp camel_key(key) when is_atom(key), do: key |> Atom.to_string() |> camel_key()

  defp camel_key(key) when is_binary(key) do
    case String.split(key, "_") do
      [first | rest] -> first <> Enum.map_join(rest, "", &String.capitalize/1)
      [] -> key
    end
  end
end
