defmodule Shroud.Email.Unsubscribe do
  @moduledoc """
  Builds unsubscribe headers from verified sender metadata or an alias-scoped capability.
  """

  import Ecto.Query

  alias Shroud.{Aliases, Mailer, Repo, Util}
  alias Shroud.Email.UnsubscribeRelay
  alias ShroudWeb.Endpoint

  @salt "alias unsubscribe"
  @marker "List-Unsubscribe=One-Click"
  @relay_validity_days 90
  @max_unsubscribe_bytes 4096

  def add_headers(email, user, email_alias, sender, message) do
    original = verified_headers(message.headers)

    case {user.unsubscribe_behavior, original} do
      {behavior, {:ok, unsubscribe, post}}
      when behavior in [:forward_then_block, :forward_then_disable] ->
        email =
          Swoosh.Email.header(
            email,
            "List-Unsubscribe",
            rewrite_mailto(unsubscribe, email_alias)
          )

        if post, do: Swoosh.Email.header(email, "List-Unsubscribe-Post", post), else: email

      {behavior, _} ->
        action =
          if behavior in [:forward_then_disable, :always_disable], do: :disable, else: :block

        url = Endpoint.url() <> "/unsubscribe/" <> token(email_alias, action, sender)

        email
        |> Swoosh.Email.header("List-Unsubscribe", "<#{url}>")
        |> Swoosh.Email.header("List-Unsubscribe-Post", @marker)
    end
  end

  def token(email_alias, action, sender) when action in [:block, :disable] do
    Phoenix.Token.encrypt(
      Endpoint,
      @salt,
      {email_alias.id, email_alias.unsubscribe_generation, action, String.downcase(sender)}
    )
  end

  def consume(token) do
    with {:ok, {id, generation, action, sender}} <-
           Phoenix.Token.decrypt(Endpoint, @salt, token, max_age: :infinity),
         true <-
           is_integer(id) and is_integer(generation) and action in [:block, :disable] and
             is_binary(sender) do
      Aliases.unsubscribe(id, generation, action, sender)
    else
      _ -> {:error, :invalid}
    end
  end

  def relay_address?(address) do
    {local, domain} = Util.extract_email_parts(String.downcase(address))

    domain == String.downcase(Util.email_domain()) and
      Regex.match?(~r/^unsubscribe_[0-9a-f]{48}$/, local)
  end

  def prune_relays do
    Repo.delete_all(
      from relay in UnsubscribeRelay,
        join: email_alias in assoc(relay, :alias),
        where:
          relay.inserted_at <= ago(@relay_validity_days, "day") or
            relay.generation != email_alias.unsubscribe_generation or
            not is_nil(email_alias.deleted_at)
    )
  end

  def relay_email(sender, recipient) do
    {local, _domain} = Util.extract_email_parts(String.downcase(recipient))
    token_hash = :crypto.hash(:sha256, String.replace_prefix(local, "unsubscribe_", ""))

    authorized =
      Repo.one(
        from relay in UnsubscribeRelay,
          join: email_alias in assoc(relay, :alias),
          join: user in assoc(email_alias, :user),
          where:
            relay.token_hash == ^token_hash and
              relay.generation == email_alias.unsubscribe_generation,
          where: is_nil(email_alias.deleted_at) and user.email == ^sender,
          where: relay.inserted_at > ago(@relay_validity_days, "day"),
          where: user.status in [:active, :lifetime, :free],
          select: {relay.recipe, email_alias.address}
      )

    case authorized do
      {recipe, address} ->
        %{"recipient" => destination, "subject" => subject, "body" => body} =
          Jason.decode!(recipe)

        # Reconstruct only the verified unsubscribe request. Submitted content,
        # recipients, headers and attachments cannot turn it into an ordinary reply.
        Swoosh.Email.new()
        |> Swoosh.Email.from(address)
        |> Swoosh.Email.to(destination)
        |> Swoosh.Email.subject(subject)
        |> Swoosh.Email.text_body(body)
        |> Mailer.deliver()
        |> case do
          {:ok, _} -> :ok
          {:error, _} = error -> error
        end

      nil ->
        :ok
    end
  end

  # Haraka authenticates these values after verifying the original message. Raw
  # List-Unsubscribe and Authentication-Results headers are never trusted here.
  defp verified_headers(headers) do
    secret = Application.get_env(:shroud, :unsubscribe_attestation_secret)

    with true <- is_binary(secret) and byte_size(secret) > 0,
         value when is_binary(value) and byte_size(value) <= 16_384 <-
           Map.get(headers, "x-shroud-unsubscribe"),
         [payload, mac] <- String.split(value, "."),
         {:ok, signature} <- Base.url_decode64(mac, padding: false),
         expected = :crypto.mac(:hmac, :sha256, secret, "shroud-unsubscribe:" <> payload),
         true <- Plug.Crypto.secure_compare(expected, signature),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"unsubscribe" => unsubscribe, "post" => post, "timestamp" => timestamp}} <-
           Jason.decode(json),
         true <-
           is_integer(timestamp) and timestamp <= System.system_time(:second) + 60 and
             timestamp >= System.system_time(:second) - 604_800,
         true <- usable_headers?(unsubscribe, post) do
      {:ok, unsubscribe, post}
    else
      _ -> :error
    end
  end

  defp usable_headers?(unsubscribe, _post)
       when is_binary(unsubscribe) and byte_size(unsubscribe) > @max_unsubscribe_bytes,
       do: false

  defp usable_headers?(unsubscribe, post)
       when is_binary(unsubscribe) and post in [nil, @marker] do
    urls = Regex.scan(~r/<([^<>\s]+)>/, unsubscribe, capture: :all_but_first) |> List.flatten()
    remainder = Regex.replace(~r/<[^<>\s]+>/, unsubscribe, "")

    valid =
      urls != [] and Regex.match?(~r/^\s*(,\s*)*$/, remainder) and
        not String.contains?(unsubscribe, ["\r", "\n"]) and
        not Regex.match?(~r/%(?![0-9a-fA-F]{2})/, unsubscribe)

    uris =
      Enum.map(urls, fn url ->
        case URI.new(url) do
          {:ok, uri} -> uri
          {:error, _} -> nil
        end
      end)

    valid and Enum.all?(uris, &usable_uri?/1) and one_click_uris?(uris, post)
  end

  defp usable_headers?(_, _), do: false

  defp one_click_uris?(_uris, nil), do: true

  defp one_click_uris?(uris, @marker) do
    Enum.count(uris, &(&1.scheme == "https")) == 1 and
      Enum.all?(uris, &(&1.scheme != "http"))
  end

  defp usable_uri?(%URI{scheme: scheme, host: host, userinfo: nil})
       when scheme in ["https", "http"], do: is_binary(host) and host != ""

  defp usable_uri?(%URI{scheme: "mailto", path: address, query: query, fragment: nil})
       when is_binary(address) do
    decoded = URI.decode(address)

    String.valid?(decoded) and
      Regex.match?(~r/^[^\s\x00-\x1f\x7f@,<>"?]+@[^\s\x00-\x1f\x7f@,<>"?]+$/, decoded) and
      valid_mailto_fields?(query)
  end

  defp usable_uri?(_), do: false

  defp mailto_fields(query) do
    (query || "")
    |> String.split("&", trim: true)
    |> Enum.map(fn field ->
      [key | value] = String.split(field, "=", parts: 2)
      {String.downcase(URI.decode(key)), URI.decode(Enum.join(value))}
    end)
  end

  defp valid_mailto_fields?(query) do
    fields = mailto_fields(query)
    keys = Enum.map(fields, &elem(&1, 0))

    Enum.all?(keys, &(&1 in ["subject", "body"])) and
      Enum.all?(fields, fn {_, value} -> String.valid?(value) end) and
      length(keys) == length(Enum.uniq(keys)) and
      not String.contains?(Map.get(Map.new(fields), "subject", ""), ["\r", "\n", "\0"])
  end

  defp rewrite_mailto(value, email_alias) do
    Regex.replace(~r/<mailto:([^>?]+)(\?[^>]*)?>/i, value, fn _, recipient, query ->
      fields = mailto_fields(String.trim_leading(query, "?")) |> Map.new()

      recipe =
        Jason.encode!(%{
          recipient: URI.decode(recipient),
          subject: Map.get(fields, "subject", "unsubscribe"),
          body: Map.get(fields, "body", "unsubscribe")
        })

      payload =
        :erlang.term_to_binary({email_alias.id, email_alias.unsubscribe_generation, recipe})

      token =
        :crypto.mac(
          :hmac,
          :sha256,
          Endpoint.config(:secret_key_base),
          "mailto unsubscribe:" <> payload
        )
        |> binary_part(0, 24)
        |> Base.encode16(case: :lower)

      Repo.insert!(
        %UnsubscribeRelay{
          token_hash: :crypto.hash(:sha256, token),
          recipe: recipe,
          generation: email_alias.unsubscribe_generation,
          alias_id: email_alias.id
        },
        on_conflict: {:replace, [:inserted_at]},
        conflict_target: :token_hash
      )

      "<mailto:unsubscribe_" <> token <> "@" <> Util.email_domain() <> query <> ">"
    end)
  end
end
