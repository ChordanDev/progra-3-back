defmodule MyFoodBackWeb.ErrorRendering do
  @moduledoc """
  Helpers for rendering error maps into JSON-safe shapes.

  `Accounts` returns error maps that may include a `:changeset` field for
  internal diagnostics. That struct is not directly JSON-encodable and is
  not useful to clients, so we strip it before delegating to the existing
  camelize JSON layer.
  """

  @internal_keys [:changeset, :error]

  def safe_error(%_{} = struct), do: safe_error(Map.from_struct(struct))

  def safe_error(error) when is_map(error) and not is_struct(error) do
    Map.drop(error, @internal_keys)
  end

  def safe_error(error), do: error
end
