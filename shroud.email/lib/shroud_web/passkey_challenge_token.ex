defmodule ShroudWeb.PasskeyChallengeToken do
  import Plug.Conn, only: [get_session: 2]

  @salt "passkey-challenge"

  def sign(conn, token) do
    Phoenix.Token.sign(ShroudWeb.Endpoint, @salt, {token, get_session(conn, :_csrf_token)})
  end

  def verify(conn, signed) when is_binary(signed) do
    case Phoenix.Token.verify(ShroudWeb.Endpoint, @salt, signed, max_age: 300) do
      {:ok, {token, csrf}} when is_binary(token) ->
        if csrf == get_session(conn, :_csrf_token), do: {:ok, token}, else: :error

      _ ->
        :error
    end
  end

  def verify(_, _), do: :error
end
