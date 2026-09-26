defmodule ShroudWeb.PasskeyRegistrationController do
  use ShroudWeb, :controller

  alias Shroud.Accounts
  alias Shroud.Accounts.{Passkeys, User}

  def options(conn, %{"passkey" => %{"current_password" => password}}) do
    options(conn, %{"current_password" => password})
  end

  def options(conn, %{"current_password" => password}) do
    user = conn.assigns.current_user

    if User.valid_password?(user, password) do
      {:ok, options} = Passkeys.begin_registration(user)

      conn
      |> put_session(:passkey_registration_token, options.token)
      |> json(%{
        publicKey: %{
          challenge: options.challenge,
          rp: %{id: options.rp_id, name: "Shroud.email"},
          user: %{
            id: options.user_handle,
            name: options.user_email,
            displayName: options.user_email
          },
          pubKeyCredParams: [%{type: "public-key", alg: -7}, %{type: "public-key", alg: -257}],
          authenticatorSelection: %{residentKey: "required", userVerification: "required"},
          excludeCredentials:
            Enum.map(options.exclude_credentials, &%{type: "public-key", id: &1}),
          attestation: "none",
          timeout: 300_000
        }
      })
    else
      conn |> put_status(:forbidden) |> json(%{error: "Could not authorize passkey registration"})
    end
  end

  def options(conn, _), do: conn |> put_status(:forbidden) |> json(%{error: "Invalid request"})

  def create(conn, params) do
    token = get_session(conn, :passkey_registration_token)
    conn = delete_session(conn, :passkey_registration_token)

    result =
      with {:ok, attestation} <- decode(params["attestationObject"]),
           {:ok, client_data} <- decode(params["clientDataJSON"]),
           {:ok, raw_id} <- decode(params["rawId"]),
           true <- is_binary(token) do
        Passkeys.register(
          conn.assigns.current_user,
          token,
          attestation,
          client_data,
          params["label"] || "Passkey",
          raw_id
        )
      else
        _ ->
          if is_binary(token),
            do: Passkeys.consume_challenge(token, :registration, conn.assigns.current_user)

          {:error, :invalid_registration}
      end

    case result do
      {:ok, credential} ->
        json(conn, %{id: Base.url_encode64(credential.credential_id, padding: false)})

      _ ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "Could not add passkey"})
    end
  end

  def delete(conn, %{"id" => id, "passkey" => %{"current_password" => password}}) do
    delete(conn, %{"id" => id, "current_password" => password})
  end

  def delete(conn, %{"id" => id, "current_password" => password}) do
    with true <- User.valid_password?(conn.assigns.current_user, password),
         {:ok, raw_id} <- decode(id),
         :ok <- Accounts.remove_passkey(conn.assigns.current_user, raw_id) do
      conn |> put_flash(:info, "Passkey removed.") |> redirect(to: ~p"/settings/security")
    else
      _ ->
        conn
        |> put_flash(:error, "Could not remove passkey.")
        |> redirect(to: ~p"/settings/security")
    end
  end

  def delete(conn, _),
    do:
      conn
      |> put_flash(:error, "Could not remove passkey.")
      |> redirect(to: ~p"/settings/security")

  defp decode(value) when is_binary(value) and byte_size(value) <= 24_000 do
    Base.url_decode64(value, padding: false)
  end

  defp decode(_), do: :error
end
