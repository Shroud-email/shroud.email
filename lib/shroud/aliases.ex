defmodule Shroud.Aliases do
  @moduledoc """
  The Aliases context.
  """

  import Ecto.Query, warn: false
  alias Shroud.Repo

  alias Shroud.Aliases.EmailAlias

  def list_aliases!(user) do
    user
    |> Ecto.assoc(:aliases)
    |> Repo.all()
  end

  def create_email_alias(attrs) do
    %EmailAlias{}
    |> EmailAlias.changeset(attrs)
    |> Repo.insert()
  end

  def get_email_alias(id) do
    Repo.get(EmailAlias, id)
  end

  def create_random_email_alias(user) do
    email_alias = %{
      user_id: user.id,
      address: generate_email_address()
    }
    create_email_alias(email_alias)
  end

  def delete_email_alias(id) do
    email_alias = get_email_alias(id)
    Repo.delete(email_alias)
  end

  defp generate_email_address() do
    letters = "abcdefghijklmnopqrstuvwxyz"
    numbers = "0123456789"
    alphabet = letters <> String.upcase(letters) <> numbers |> String.split("")
    address = Enum.reduce(1..16, [], fn (_, acc) -> [Enum.random(alphabet) | acc] end) |> Enum.join("")
    address = address <> "@example.com"

    if Repo.exists?(from a in EmailAlias, where: a.address == ^address) do
      generate_email_address()
    else
      address
    end
  end

end
