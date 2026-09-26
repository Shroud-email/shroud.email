defmodule Shroud.Accounts.Passkeys do
  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias Shroud.Accounts.{PasskeyChallenge, PasskeyCredential, User}
  alias Shroud.Repo

  @challenge_timeout 300

  def allow_request?(remote_ip, kind) when kind in [:options, :verify] do
    minute = div(System.system_time(:second), 60)
    source = :crypto.hash(:sha256, :erlang.term_to_binary({remote_ip, kind}))
    limit = if kind == :options, do: 30, else: 60

    %{rows: [[attempts]]} =
      SQL.query!(
        Repo,
        """
        INSERT INTO passkey_rate_limits (source, minute, attempts) VALUES ($1, $2, 1)
        ON CONFLICT (source, minute) DO UPDATE SET attempts = passkey_rate_limits.attempts + 1
        RETURNING attempts
        """,
        [source, minute]
      )

    if kind == :options do
      SQL.query!(Repo, "DELETE FROM passkey_rate_limits WHERE minute < $1", [
        minute - 2
      ])
    end

    attempts <= limit
  end

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

  def register(user, token, attestation, client_data, label, raw_id \\ nil)

  def register(%User{} = user, token, attestation, client_data, label, raw_id)
      when is_binary(attestation) and byte_size(attestation) <= 16_384 and
             is_binary(client_data) and byte_size(client_data) <= 4_096 and
             is_binary(label) and byte_size(label) <= 100 do
    with {:ok, challenge} <- consume_challenge(token, :registration, user),
         {:ok, {auth_data, _attestation_result}} <-
           verify_registration(attestation, client_data, challenge),
         %{credential_id: id, credential_public_key: key} <- auth_data.attested_credential_data,
         true <- is_nil(raw_id) or raw_id == id,
         {:ok, credential} <-
           %PasskeyCredential{user_id: user.id}
           |> PasskeyCredential.changeset(%{
             credential_id: id,
             public_key: encode_public_key(key),
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
    key
    |> Map.new(fn {k, value} ->
      {k, if(is_binary(value), do: %CBOR.Tag{tag: :bytes, value: value}, else: value)}
    end)
    |> CBOR.encode()
  end

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
    old_count = credential.sign_count

    cond do
      old_count > 0 and new_count > 0 and new_count <= old_count ->
        {:error, :counter_rollback}

      new_count > old_count ->
        case Repo.update_all(
               from(c in PasskeyCredential,
                 where: c.id == ^credential.id and c.sign_count < ^new_count
               ),
               set: [sign_count: new_count]
             ) do
          {1, _} -> :ok
          _ -> {:error, :counter_rollback}
        end

      true ->
        :ok
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
