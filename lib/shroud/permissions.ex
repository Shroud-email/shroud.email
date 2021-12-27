defmodule Shroud.Permissions do
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Accounts.User
  alias Shroud.Accounts

  defimpl Canada.Can, for: User do
    # Users can always read, update, destroy their own aliases
    def can?(%User{id: user_id}, action, %EmailAlias{user_id: user_id})
        when action in [:read, :update, :destroy],
        do: true

    # Users can only create aliases when active
    def can?(%User{} = user, :create, EmailAlias) do
      Accounts.active?(user)
    end
  end
end
