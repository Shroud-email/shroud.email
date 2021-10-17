defmodule Shroud.AliasesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Shroud.Aliases` context.
  """

  def unique_alias_email, do: "alias#{System.unique_integer()}@example.com"

  def valid_alias_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      address: unique_alias_email()
    })
  end

  def alias_fixture(attrs \\ %{}) do
    {:ok, alias} =
      attrs
      |> valid_alias_attributes()
      |> Shroud.Aliases.create_email_alias()

    alias
  end
end
