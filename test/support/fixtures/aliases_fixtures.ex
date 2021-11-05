defmodule Shroud.AliasesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Shroud.Aliases` context.
  """

  alias Shroud.Repo
  alias Shroud.Aliases.EmailMetric

  def unique_alias_email, do: "alias#{System.unique_integer()}@example.com"

  def valid_alias_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      address: unique_alias_email()
    })
  end

  def alias_fixture(attrs \\ %{}) do
    {:ok, email_alias} =
      attrs
      |> valid_alias_attributes()
      |> Shroud.Aliases.create_email_alias()

    email_alias
  end

  def metric_fixture(attrs \\ %{}) do
    changeset = EmailMetric.changeset(%EmailMetric{}, attrs)
    {:ok, metric} = Repo.insert(changeset)

    metric
  end
end
