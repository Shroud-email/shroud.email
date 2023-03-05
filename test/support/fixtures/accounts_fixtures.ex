defmodule Shroud.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Shroud.Accounts` context.
  """
  alias Shroud.Accounts
  alias Shroud.Accounts.User
  alias Shroud.Repo

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      status: :active,
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    tomorrow = NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :day)

    attrs =
      Map.merge(
        %{
          trial_expires_at: tomorrow
        },
        attrs
      )

    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user =
      user
      |> User.status_changeset(attrs)
      |> Repo.update!(returning: true)

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end
end
