defmodule Shroud.Accounts.Passkeys do
  import Ecto.Query

  alias Shroud.Accounts.{PasskeyChallenge, PasskeyCredential, User}
  alias Shroud.Repo

  @challenge_timeout 300

  def decode_base64url(value) when is_binary(value) and byte_size(value) <= 24_000 do
    Base.url_decode64(value, padding: false)
  end

  def decode_base64url(_), do: :error

  def origin_and_rp_id do
    origin = ShroudWeb.Endpoint.url()
    uri = URI.parse(origin)

    unless allowed_scheme?(uri) and is_binary(uri.host) and uri.userinfo == nil and
             uri.path in [nil, ""] and
             uri.query == nil and uri.fragment == nil do
      raise ArgumentError, "passkey origin must be an HTTPS origin (or localhost)"
    end

    {origin, uri.host}
  end

  defp allowed_scheme?(%URI{scheme: "https"}), do: true
  defp allowed_scheme?(%URI{scheme: "http", host: "localhost"}), do: true
  defp allowed_scheme?(_), do: false

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

  def register(user, token, attestation, client_data, label, raw_id \\ nil)

  def register(%User{} = user, token, attestation, client_data, label, raw_id)
      when is_binary(token) do
    with {:ok, challenge} <- consume_challenge(token, :registration, user),
         true <- valid_registration_payload?(attestation, client_data, label),
         {:ok, {auth_data, _attestation_result}} <-
           verify_registration(attestation, client_data, challenge),
         %{credential_id: id, credential_public_key: key} <- auth_data.attested_credential_data,
         true <- is_binary(id) and byte_size(id) in 1..1_024,
         true <- is_nil(raw_id) or raw_id == id,
         {:ok, public_key} <- encode_public_key(key),
         {:ok, credential} <-
           %PasskeyCredential{user_id: user.id}
           |> PasskeyCredential.changeset(%{
             credential_id: id,
             public_key: public_key,
             label: label,
             sign_count: auth_data.sign_count
           })
           |> Repo.insert() do
      {:ok, credential}
    else
      _ -> {:error, :invalid_registration}
    end
  end

  def register(_, _, _, _, _, _), do: {:error, :invalid_registration}

  defp valid_registration_payload?(attestation, client_data, label)
       when is_binary(attestation) and byte_size(attestation) <= 16_384 and
              is_binary(client_data) and byte_size(client_data) <= 4_096 and
              is_binary(label) and byte_size(label) <= 100,
       do: true

  defp valid_registration_payload?(_, _, _), do: false

  def authenticate(token, raw_id, user_handle, auth_data, signature, client_data)
      when is_binary(raw_id) and is_binary(user_handle) and is_binary(auth_data) and
             is_binary(signature) and is_binary(client_data) do
    authenticate_binaries(token, raw_id, user_handle, auth_data, signature, client_data)
  end

  def authenticate(token, _, _, _, _, _) do
    if is_binary(token), do: consume_challenge(token, :authentication, nil)
    {:error, :invalid_assertion}
  end

  defp authenticate_binaries(token, raw_id, user_handle, auth_data, signature, client_data)
       when byte_size(raw_id) <= 1_024 and byte_size(user_handle) <= 64 and
              byte_size(auth_data) <= 16_384 and byte_size(signature) <= 1_024 and
              byte_size(client_data) <= 4_096 do
    verify_authentication(token, raw_id, user_handle, auth_data, signature, client_data)
  end

  defp authenticate_binaries(token, _, _, _, _, _) do
    if is_binary(token), do: consume_challenge(token, :authentication, nil)
    {:error, :invalid_assertion}
  end

  defp verify_authentication(token, raw_id, user_handle, auth_data, signature, client_data) do
    with {:ok, challenge} <- consume_challenge(token, :authentication, nil),
         %PasskeyCredential{} = credential <- Shroud.Accounts.get_passkey(raw_id),
         %User{} = user <- Repo.get(User, credential.user_id),
         true <- Plug.Crypto.secure_compare(user.passkey_handle, user_handle),
         {:ok, key} <- decode_public_key(credential.public_key),
         {:ok, verified} <-
           verify_assertion(raw_id, auth_data, signature, client_data, challenge, key),
         :ok <- update_counter(credential, verified.sign_count) do
      {:ok, user}
    else
      _ -> {:error, :invalid_assertion}
    end
  end

  defp encode_public_key(key) do
    with {:ok, fields} <- public_key_fields(key) do
      encoded =
        key
        |> Map.take(fields)
        |> Map.new(fn {k, value} ->
          {k, if(is_binary(value), do: %CBOR.Tag{tag: :bytes, value: value}, else: value)}
        end)
        |> CBOR.encode()

      {:ok, encoded}
    end
  end

  defp public_key_fields(%{1 => 2, 3 => -7, -1 => 1, -2 => x, -3 => y})
       when is_binary(x) and byte_size(x) == 32 and is_binary(y) and byte_size(y) == 32 do
    # ECDH validates that the supplied point belongs to P-256.
    :crypto.compute_key(:ecdh, <<4, x::binary, y::binary>>, <<1>>, :secp256r1)
    {:ok, [1, 3, -1, -2, -3]}
  rescue
    _ in [ErlangError, ArgumentError] -> {:error, :invalid_key}
  end

  defp public_key_fields(%{1 => 3, 3 => -257, -1 => n, -2 => e})
       when is_binary(n) and byte_size(n) in 256..1_024 and is_binary(e) and
              byte_size(e) in 1..8 do
    modulus = :binary.decode_unsigned(n)
    exponent = :binary.decode_unsigned(e)

    if modulus >= Integer.pow(2, 2047) and rem(modulus, 2) == 1 and
         exponent >= 3 and rem(exponent, 2) == 1 and exponent < modulus,
       do: {:ok, [1, 3, -1, -2]},
       else: {:error, :invalid_key}
  end

  defp public_key_fields(_), do: {:error, :invalid_key}

  defp decode_public_key(binary) do
    case CBOR.decode(binary) do
      {:ok, key, ""} when is_map(key) ->
        {:ok,
         Map.new(key, fn
           {k, %CBOR.Tag{tag: :bytes, value: bytes}} -> {k, bytes}
           pair -> pair
         end)}

      _ ->
        {:error, :invalid_key}
    end
  rescue
    _ -> {:error, :invalid_key}
  end

  defp verify_assertion(id, auth_data, signature, client_data, challenge, key) do
    Wax.authenticate(id, auth_data, signature, client_data, challenge, [{id, key}])
  rescue
    _ -> {:error, :invalid_assertion}
  end

  defp update_counter(credential, new_count) do
    case Repo.update_all(
           from(c in PasskeyCredential,
             where:
               c.id == ^credential.id and
                 ((c.sign_count == 0 and ^new_count == 0) or c.sign_count < ^new_count)
           ),
           set: [sign_count: new_count]
         ) do
      {1, _} -> :ok
      _ -> {:error, :counter_rollback}
    end
  end

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
