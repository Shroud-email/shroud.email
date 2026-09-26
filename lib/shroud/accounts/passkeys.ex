defmodule Shroud.Accounts.Passkeys do
  import Ecto.Query

  alias Shroud.Accounts.{PasskeyChallenge, PasskeyCredential, User}
  alias Shroud.Repo

  @challenge_timeout 300

  def origin_and_rp_id do
    origin = Application.get_env(:shroud, :passkey_origin) || ShroudWeb.Endpoint.url()
    uri = URI.parse(origin)

    unless (uri.scheme == "https" or (uri.scheme == "http" and uri.host == "localhost")) and
             is_binary(uri.host) and uri.userinfo == nil and uri.path in [nil, ""] do
      raise ArgumentError, "passkey origin must be an HTTPS origin (or localhost)"
    end

    {origin, uri.host}
  end

  def begin_registration(%User{} = user) do
    challenge = Wax.new_registration_challenge(challenge_options())
    options = store_challenge(challenge, user.id)

    {:ok,
     Map.merge(options, %{
       user_handle: Base.url_encode64(user.passkey_handle, padding: false),
       user_email: user.email,
       exclude_credentials:
         Shroud.Accounts.list_passkeys(user)
         |> Enum.map(&Base.url_encode64(&1.credential_id, padding: false))
     })}
  end

  def begin_authentication do
    challenge = Wax.new_authentication_challenge(challenge_options())
    {:ok, store_challenge(challenge, nil)}
  end

  def register(%User{} = user, token, attestation, client_data, label)
      when is_binary(attestation) and byte_size(attestation) <= 16_384 and
             is_binary(client_data) and byte_size(client_data) <= 4_096 and
             is_binary(label) and byte_size(label) <= 100 do
    with {:ok, challenge} <- consume_challenge(token, :registration, user),
         {:ok, {auth_data, _attestation_result}} <-
           verify_registration(attestation, client_data, challenge),
         %{credential_id: id, credential_public_key: key} <- auth_data.attested_credential_data,
         {:ok, credential} <-
           %PasskeyCredential{user_id: user.id}
           |> PasskeyCredential.changeset(%{
             credential_id: id,
             public_key: :erlang.term_to_binary(key),
             label: label,
             sign_count: auth_data.sign_count
           })
           |> Repo.insert() do
      {:ok, credential}
    else
      _ -> {:error, :invalid_registration}
    end
  end

  def register(_, _, _, _, _), do: {:error, :invalid_registration}

  defp verify_registration(attestation, client_data, challenge) do
    Wax.register(attestation, client_data, challenge)
  rescue
    _ -> {:error, :invalid_registration}
  end

  def consume_challenge(token, kind, user) when is_binary(token) do
    now = DateTime.utc_now()

    query =
      from c in PasskeyChallenge,
        where: c.token == ^token and c.kind == ^Atom.to_string(kind) and c.expires_at > ^now,
        select: c

    query =
      case user do
        nil -> where(query, [c], is_nil(c.user_id))
        %User{id: user_id} -> where(query, [c], c.user_id == ^user_id)
      end

    case Repo.delete_all(query) do
      {1, [stored]} ->
        options = challenge_options()

        challenge =
          case kind do
            :registration -> Wax.new_registration_challenge(options)
            :authentication -> Wax.new_authentication_challenge(options)
          end

        {:ok, %{challenge | bytes: stored.bytes, issued_at: stored.issued_at}}

      _ ->
        {:error, :invalid_challenge}
    end
  end

  defp challenge_options do
    {origin, rp_id} = origin_and_rp_id()
    [origin: origin, rp_id: rp_id, timeout: @challenge_timeout, user_verification: "required"]
  end

  defp store_challenge(challenge, user_id) do
    Repo.delete_all(from c in PasskeyChallenge, where: c.expires_at < ^DateTime.utc_now())
    token = :crypto.strong_rand_bytes(32)

    %PasskeyChallenge{
      token: token,
      bytes: challenge.bytes,
      kind: if(challenge.type == :attestation, do: "registration", else: "authentication"),
      user_id: user_id,
      issued_at: challenge.issued_at,
      expires_at: DateTime.add(DateTime.utc_now(), @challenge_timeout)
    }
    |> Repo.insert!()

    %{
      token: token,
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rp_id: challenge.rp_id
    }
  end
end
