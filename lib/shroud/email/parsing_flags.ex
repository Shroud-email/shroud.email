defmodule Shroud.Email.ParsingFlags do
  alias Shroud.Accounts.User

  @mailex_flag :mailex_parsing

  @spec mailex_parsing_enabled?(User.t() | nil) :: boolean()
  def mailex_parsing_enabled?(nil), do: false

  def mailex_parsing_enabled?(%User{} = user) do
    FunWithFlags.enabled?(@mailex_flag, for: user)
  end
end
