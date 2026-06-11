defmodule MyFoodBack.Accounts.SlotCookingTimes do
  @moduledoc """
  Owns the slot-cooking-times domain decisions that used to live as private
  constants and helpers inside `MyFoodBack.Accounts`:

    * which meal slots and hunger levels are valid,
    * the per-slot JSON-shape defaults,
    * the key whitelist used to coerce a slot's value map (camelCase, snake_case,
      atom), and
    * the canonical JSON shape returned to clients (saved rows merged with
      defaults).

  This module is intentionally pure: it never touches the database. The
  `MyFoodBack.Accounts` context stays responsible for loading, persisting and
  transacting; it delegates the slot-domain decisions here.
  """

  @supported_slots ~w(breakfast lunch dinner)
  @hunger_levels ~w(light normal strong)

  @slot_atom_keys %{
    "breakfast" => :breakfast,
    "lunch" => :lunch,
    "dinner" => :dinner
  }

  @slot_defaults %{
    "breakfast" => 0,
    "lunch" => 0,
    "dinner" => 0
  }

  @hunger_defaults %{
    "breakfast" => "normal",
    "lunch" => "normal",
    "dinner" => "normal"
  }

  @value_keys %{
    "mealSlot" => :meal_slot,
    "meal_slot" => :meal_slot,
    :meal_slot => :meal_slot,
    "cookingTimeMinutes" => :cooking_time_minutes,
    "cooking_time_minutes" => :cooking_time_minutes,
    :cooking_time_minutes => :cooking_time_minutes,
    "hungerLevel" => :hunger_level,
    "hunger_level" => :hunger_level,
    :hunger_level => :hunger_level
  }

  @doc "The three supported meal slots, in canonical order."
  @spec supported_slots() :: [String.t()]
  def supported_slots, do: @supported_slots

  @doc "The supported hunger levels."
  @spec hunger_levels() :: [String.t()]
  def hunger_levels, do: @hunger_levels

  @doc """
  Returns true if `slot` is one of the supported meal slots. Accepts strings
  and atoms (e.g. `:breakfast` or `"breakfast"`).
  """
  @spec supported_slot?(any()) :: boolean()
  def supported_slot?(slot) do
    slot in @supported_slots or slot in Map.values(@slot_atom_keys)
  end

  @doc """
  Returns the canonical JSON-shape defaults for the three slots. The map is
  shaped exactly as the API returns it to clients.
  """
  @spec defaults() :: %{String.t() => %{String.t() => non_neg_integer() | String.t()}}
  def defaults do
    for slot <- @supported_slots, into: %{} do
      {slot, canonical_value(%{cooking_time_minutes: Map.fetch!(@slot_defaults, slot), hunger_level: Map.fetch!(@hunger_defaults, slot)})}
    end
  end

  @doc """
  The whitelist used by `Accounts` to coerce a slot's value map (camelCase,
  snake_case, atom) into the atom-keyed shape the Ecto changeset expects.
  """
  @spec value_keys() :: %{(String.t() | atom()) => atom()}
  def value_keys, do: @value_keys

  @doc """
  Looks up a slot's raw value in a slot map, accepting either a string key
  (e.g. `"breakfast"`) or its atom equivalent (`:breakfast`). Returns the
  value, or `nil` if the slot is not present.
  """
  @spec fetch_slot(map(), String.t() | atom()) :: any() | nil
  def fetch_slot(slots, slot) when is_map(slots) do
    Map.get(slots, slot) || Map.get(slots, Map.fetch!(@slot_atom_keys, slot))
  end

  @doc """
  Coerces a slot-cooking-times payload (with atom-or-string top-level keys)
  to a map keyed by string slot names. Used by `Accounts.update_slot_cooking_times/2`
  before validation.
  """
  @spec stringify_keys(map()) :: %{String.t() => any()}
  def stringify_keys(attrs) when is_map(attrs) do
    for {slot, value} <- attrs, into: %{}, do: {to_string(slot), value}
  end

  @doc """
  Returns the canonical JSON-shape value for a saved row.
  """
  @spec canonical_value(%{
          required(:cooking_time_minutes) => non_neg_integer(),
          required(:hunger_level) => String.t()
        }) :: %{String.t() => non_neg_integer() | String.t()}
  def canonical_value(%{cooking_time_minutes: minutes, hunger_level: hunger_level}) do
    %{"cookingTimeMinutes" => minutes, "hungerLevel" => hunger_level}
  end

  @doc """
  Merges a list of saved `UserSlotCookingTime` rows with the slot defaults to
  produce the canonical JSON-shape map returned by `Accounts.get_slot_cooking_times/1`.
  """
  @spec merge_with_defaults([map()]) :: %{String.t() => %{String.t() => non_neg_integer() | String.t()}}
  def merge_with_defaults(rows) do
    base = defaults()

    Enum.reduce(rows, base, fn row, acc ->
      Map.put(acc, row.meal_slot, canonical_value(row))
    end)
  end

  @doc """
  Returns `:ok` if `normalized` is a valid three-slot payload (one entry per
  supported slot, each entry shaped as a map with `"cookingTimeMinutes"` and
  `"hungerLevel"`), otherwise `{:error, code, reason}` where `code` is the
  public error code returned to the client.
  """
  @spec validate_payload(%{String.t() => any()}) ::
          :ok | {:error, String.t(), String.t()}
  def validate_payload(normalized) when is_map(normalized) do
    cond do
      map_size(normalized) != 3 ->
        {:error, "slot_cooking_times_invalid", "expected 3 slots"}

      not Enum.all?(@supported_slots, &Map.has_key?(normalized, &1)) ->
        {:error, "slot_cooking_times_invalid", "missing required slot"}

      Enum.any?(normalized, fn {_slot, value} ->
        not (is_map(value) and Map.has_key?(value, "cookingTimeMinutes") and
                 Map.has_key?(value, "hungerLevel"))
      end) ->
        {:error, "slot_cooking_times_invalid", "missing required field"}

      true ->
        :ok
    end
  end
end
