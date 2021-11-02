defmodule Shroud.Permissions do
  alias Shroud.Aliases.EmailAlias
  alias Shroud.Accounts.User

  defimpl Canada.Can, for: User do
    def can?(%User{id: user_id}, action, %EmailAlias{user_id: user_id})
        when action in [:read, :update, :destroy],
        do: true

    def can?(%User{}, :create, EmailAlias), do: true
  end
end
