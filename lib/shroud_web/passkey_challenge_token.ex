defmodule ShroudWeb.PasskeyChallengeToken do
  import Plug.Conn, only: [get_session: 2]

  @salt "passkey-challenge"

  def sign(conn, token) do
    Phoenix.Token.sign(ShroudWeb.Endpoint, @salt, {token, get_session(conn, :_csrf_token)})
  end

  def verify(conn, signed) when is_binary(signed) do
    case Phoenix.Token.verify(ShroudWeb.Endpoint, @salt, signed, max_age: 300) do
      {:ok, {token, csrf}} when is_binary(token) ->
        session_csrf = get_session(conn, :_csrf_token)

        if is_binary(csrf) and is_binary(session_csrf) and
             Plug.Crypto.secure_compare(csrf, session_csrf),
           do: {:ok, token},
           else: :error

      _ ->
        :error
    end
  end

  def verify(_, _), do: :error
end
