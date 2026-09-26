defmodule ShroudWeb.PasskeySessionController do
  use ShroudWeb, :controller

  alias Shroud.Accounts.Passkeys
  alias ShroudWeb.{PasskeyChallengeToken, UserAuth}

  def options(conn, _params) do
    if Passkeys.allow_request?(Passkeys.request_ip(conn), :options) do
      {:ok, options} = Passkeys.begin_authentication()

      json(conn, %{
        token: PasskeyChallengeToken.sign(conn, options.token),
        publicKey: %{
          challenge: options.challenge,
          rpId: options.rp_id,
          userVerification: "required",
          timeout: 300_000
        }
      })
    else
      conn |> put_status(:too_many_requests) |> json(%{error: "Too many passkey requests"})
    end
  end

  def create(conn, params) do
    token =
      case PasskeyChallengeToken.verify(conn, params["token"]) do
        {:ok, token} -> token
        _ -> nil
      end

    result =
      with true <- Passkeys.allow_request?(Passkeys.request_ip(conn), :verify),
           {:ok, raw_id} <- decode(params["rawId"]),
           {:ok, handle} <- decode(params["userHandle"]),
           {:ok, auth_data} <- decode(params["authenticatorData"]),
           {:ok, signature} <- decode(params["signature"]),
           {:ok, client_data} <- decode(params["clientDataJSON"]),
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
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Could not sign in with passkey"})
    end
  end

  defp decode(value) when is_binary(value) and byte_size(value) <= 24_000 do
    Base.url_decode64(value, padding: false)
  end

  defp decode(_), do: :error
end
