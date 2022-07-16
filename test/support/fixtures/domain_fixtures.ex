defmodule Shroud.DomainFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Shroud.Domain` context.
  """

  alias Shroud.Repo
  alias Shroud.Domain.CustomDomain
  import Shroud.AccountsFixtures

  @doc """
  Generate a custom_domain.
  """
  def custom_domain_fixture(attrs \\ %{}) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    user_id = if Map.get(attrs, :user_id), do: attrs.user_id, else: user_fixture().id

    attrs =
      attrs
      |> Enum.into(%{
        catchall_enabled: true,
        dkim_verified_at: now,
        dmarc_verified_at: now,
        domain: "domain#{System.unique_integer()}.com",
        mx_verified_at: now,
        spf_verified_at: now,
        verification_code: "deadbeef",
        ownership_verified_at: now,
        user_id: user_id
      })

    %CustomDomain{}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!()
  end
end
