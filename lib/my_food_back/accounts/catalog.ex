defmodule MyFoodBack.Accounts.Catalog do
  @moduledoc """
  Server-side catalog of allowed diet and hard-restriction codes.

  The MVP seed list is intentionally minimal and is owned by the product team
  (see Open Question 1 in the Slice 2 proposal). This module loads the
  configured set and exposes a single `valid?/2` entry point so callers can
  reject unknown codes without hardcoding them in the schema layer.
  """

  @diets ["omnivore", "vegetarian", "vegan", "pescatarian"]
  @hard_restrictions ["peanut", "tree_nut", "shellfish", "gluten", "dairy", "egg", "soy"]

  def valid_diet?(nil), do: true
  def valid_diet?(code) when is_binary(code), do: code in @diets
  def valid_diet?(_), do: false

  def valid_hard_restriction?(code) when is_binary(code), do: code in @hard_restrictions
  def valid_hard_restriction?(_), do: false

  def all_diets, do: @diets
  def all_hard_restrictions, do: @hard_restrictions
end
