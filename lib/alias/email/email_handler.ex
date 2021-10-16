defmodule Alias.Email.EmailHandler do
  import Swoosh.Email
  require Logger
  alias Alias.{Accounts, Mailer}

  @type header_type :: {String.t(), String.t()}
  @from_email "noreply@shroud.email"
  @from_suffix " (via Shroud)"

  def forward_email(from, [to], data) do
    # Lookup real email based on the receiving alias (`to`)
    case Accounts.get_user_by_alias(to) do
      nil ->
        Logger.info("Discarding email to unknown address #{to} (from #{from})")
        :ok

      user ->
        # TODO: handle parsing failures?
        :mimemail.decode(data)
        |> transmogrify(user.email)
        |> deliver()
    end
  end

  def forward_email(from, [first | rest], _data) do
    Logger.error("Failed to forward email from #{from} with multiple recipients: #{[first | rest]}")
  end

  # Take an email as parsed by mimemail, then convert it into a Swoosh.Email.t
  # ready to send
  defp transmogrify(email, recipient_address) do
    email =
      new()
      |> build_email(email)

    # Now we've put together our email, we modify it lightly to make it clear it came from us
    # TODO: show the alias the email was sent to in the body
    [{recipient_name, _alias}] = email.to
    {sender_name, _sender_address} = email.reply_to
    email
    |> from({sender_name <> @from_suffix, @from_email})
    |> Map.put(:to, [{recipient_name, recipient_address}])
  end

  @spec build_email(Swoosh.Email.t(), {String.t(), String.t(), [any()], any(), any()}) :: Swoosh.Email.t()
  defp build_email(email, {"text", "html", headers, _opts, body}) do
    email
    |> html_body(body)
    |> process_headers(headers)
  end

  defp build_email(email, {"text", "plain", headers, _opts, body}) do
    email
    |> text_body(body)
    |> process_headers(headers)
  end

  defp build_email(email, {"multipart", "alternative", headers, _opts, parts}) when is_list(parts) do
    parts
    |> Enum.reduce(email, fn part, acc -> build_email(acc, part) end)
    |> process_headers(headers)
  end

  @spec process_headers(Swoosh.Email.t(), [header_type]) :: Swoosh.Email.t()
  defp process_headers(email, headers) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(key), value} end)
    |> Enum.reduce(email, fn h, acc -> process_header(acc, h) end)
  end

  @spec process_header(Swoosh.Email.t(), {String.t(), any()}) :: Swoosh.Email.t()
  defp process_header(email, {"from", value}), do: reply_to(email, parse_address(value))
  defp process_header(email, {"subject", value}), do: subject(email, value)
  defp process_header(email, {"to", value}), do: to(email, parse_address(value))
  defp process_header(email, {key, value}), do: header(email, key, value)

  # Parses both `email@example.com`, `Zero Cool <email@example.com>`, and `"Zero Cool" <email@example.com>"`.
  defp parse_address(address) do
    case Regex.run(~r/^(.*)<(.*@.*)>/, address) do
      nil ->
        # Not an addr-spec
        {address, address}

      [_string, name_part, address_part] ->
        {trim_quotes_and_whitespace(name_part), String.trim(address_part)}

      _other ->
        Logger.warn("Failed to parse address: #{address}")
        {nil, address}
    end
  end

  defp trim_quotes_and_whitespace(str) do
    str
    |> String.replace(~r/^['"\s\\]+/, "")
    |> String.replace(~r/['"\s\\]+$/, "")
  end

  defp deliver(%Swoosh.Email{} = email) do
    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

end
