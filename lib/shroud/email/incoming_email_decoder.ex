defmodule Shroud.Email.IncomingEmailDecoder do
  alias Shroud.Accounts.User
  alias Shroud.Email.ParsingFlags

  @spec decode(String.t(), User.t() | nil) ::
          {:mimemail, :mimemail.mimetuple()} | {:mailex, Mailex.Message.t()}
  def decode(data, user) do
    if ParsingFlags.mailex_parsing_enabled?(user) do
      {:mailex, Mailex.parse!(data)}
    else
      {:mimemail, :mimemail.decode(data)}
    end
  end
end
