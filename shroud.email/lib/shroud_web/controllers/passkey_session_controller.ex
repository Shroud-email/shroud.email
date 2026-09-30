defmodule ShroudWeb.PasskeySessionController do
  use ShroudWeb, :controller

  alias Shroud.Accounts.Passkeys
  alias ShroudWeb.{PasskeyChallengeToken, UserAuth}

  def create(conn, params) do
    token =
      case PasskeyChallengeToken.verify(conn, params["token"]) do
        {:ok, token} -> token
        _ -> nil
      end

    result =
      with {:ok, raw_id} <- Passkeys.decode_base64url(params["rawId"]),
           {:ok, handle} <- Passkeys.decode_base64url(params["userHandle"]),
           {:ok, auth_data} <- Passkeys.decode_base64url(params["authenticatorData"]),
           {:ok, signature} <- Passkeys.decode_base64url(params["signature"]),
           {:ok, client_data} <- Passkeys.decode_base64url(params["clientDataJSON"]),
           true <- is_binary(token) do
        Passkeys.authenticate(token, raw_id, handle, auth_data, signature, client_data)
      else
        _ ->
          if is_binary(token), do: Passkeys.consume_challenge(token, :authentication, nil)
          {:error, :invalid_assertion}
      end

    case result do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      _ ->
        conn
        |> put_flash(:error, "Could not sign in with passkey. Please try again.")
        |> redirect(to: ~p"/users/log_in")
    end
  end
end
