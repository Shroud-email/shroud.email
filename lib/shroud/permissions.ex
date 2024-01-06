defmodule Shroud.Permissions do
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Accounts.User
  alias Shroud.Accounts
  alias Shroud.Email.SpamEmail
  alias Shroud.Domain.CustomDomain

  defimpl Canada.Can, for: User do
    # Users can always read, update, destroy their own aliases
    def can?(%User{id: user_id}, action, %EmailAlias{user_id: user_id})
        when action in [:read, :update, :destroy],
        do: true

    # Users can only create aliases when active
    def can?(%User{} = user, :create, EmailAlias) do
      Accounts.active?(user)
    end

    def can?(%User{id: user_id}, action, %SpamEmail{email_alias: %EmailAlias{user_id: user_id}})
        when action in [:read, :update, :destroy],
        do: true

    def can?(%User{id: user_id}, action, %CustomDomain{user_id: user_id})
        when action in [:read, :update, :destroy],
        do: true

    def can?(%User{} = user, :debug, _), do: Accounts.admin?(user)
  end
end
