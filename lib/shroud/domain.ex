defmodule Shroud.Domain do
  @moduledoc """
  The Domain context.
  """

  import Ecto.Query, warn: false
  alias Shroud.Repo
  alias Shroud.Accounts.User

  alias Shroud.Domain.CustomDomain

  @doc """
  Returns the list of custom_domains.

  ## Examples

      iex> list_custom_domains()
      [%CustomDomain{}, ...]

  """
  def list_custom_domains(%User{} = user) do
    Repo.all(from d in CustomDomain, where: d.user_id == ^user.id)
  end

  @doc """
  Gets a single custom_domain.

  Raises `Ecto.NoResultsError` if the Custom domain does not exist.
  """
  def get_custom_domain!(%User{} = user, domain) do
    Repo.get_by!(CustomDomain, user_id: user.id, domain: domain)
  end

  @doc """
  Creates a custom_domain.

  ## Examples

      iex> create_custom_domain(%{field: value})
      {:ok, %CustomDomain{}}

      iex> create_custom_domain(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_custom_domain(%User{} = user, attrs \\ %{}) do
    verification_code = "shroud-verify=#{generate_random_string()}"

    %CustomDomain{verification_code: verification_code}
    |> CustomDomain.create_changeset(attrs)
    |> Ecto.Changeset.put_assoc(:user, user)
    |> Repo.insert()
  end

  def toggle_catchall!(%CustomDomain{} = custom_domain) do
    custom_domain
    |> CustomDomain.update_changeset(%{catchall_enabled: !custom_domain.catchall_enabled})
    |> Repo.update!()
  end

  @doc """
  Deletes a custom_domain.

  ## Examples

      iex> delete_custom_domain(custom_domain)
      {:ok, %CustomDomain{}}

      iex> delete_custom_domain(custom_domain)
      {:error, %Ecto.Changeset{}}

  """
  def delete_custom_domain(%CustomDomain{} = custom_domain) do
    Repo.delete(custom_domain)
  end

  def dns_record_verified?(%CustomDomain{} = custom_domain, field) do
    one_day_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-1 * 60 * 60 * 24)
    verified_at = Map.get(custom_domain, field)

    if verified_at do
      NaiveDateTime.compare(verified_at, one_day_ago) == :gt
    else
      false
    end
  end

  def fully_verified?(%CustomDomain{} = domain) do
    fields = [
      :ownership_verified_at,
      :mx_verified_at,
      :spf_verified_at,
      :dkim_verified_at,
      :dmarc_verified_at
    ]

    Enum.all?(fields, &dns_record_verified?(domain, &1))
  end

  defp generate_random_string() do
    alphabet = "abcdefghijklmnopqrstuvwxyz1234567890" |> String.split("")
    Enum.reduce(1..20, [], fn _, acc -> [Enum.random(alphabet) | acc] end) |> Enum.join("")
  end
end
