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

  @doc """
  Builds and persists a confirmation token for `user`, returning the encoded
  (URL-safe) token string that `confirm_user/1` accepts.

  Mirrors the token-creation half of `Accounts.deliver_user_confirmation_instructions/2`
  without enqueuing the email job — useful for tests that need a valid token to
  feed to `confirm_user/1` without exercising delivery.
  """
  def generate_confirmation_token(%User{} = user) do
    {encoded_token, user_token} = Shroud.Accounts.UserToken.build_email_token(user, "confirm")
    Repo.insert!(user_token)
    encoded_token
  end
end
