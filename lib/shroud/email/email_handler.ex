defmodule Shroud.Email.EmailHandler do
  use Oban.Worker, queue: :outgoing_email

  import Swoosh.Email
  require Logger
  alias Shroud.{Accounts, Mailer}
  alias Shroud.Email.Enricher

  @type header_type :: {String.t(), String.t()}
  @from_email "noreply@shroud.email"
  @from_suffix " (via Shroud)"
  @allowed_headers [
    "from",
    "to",
    "reply-to",
    "subject",
    "date",
    "delivered-to"
  ]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"from" => from, "to" => [first | rest]}}) do
    Logger.error(
      "Failed to forward email from #{from} with multiple recipients: #{Enum.join([first | rest], ", ")}"
    )

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"from" => from, "to" => to, "data" => data}}) do
    # Lookup real email based on the receiving alias (`to`)
    case Accounts.get_user_by_alias(to) do
      nil ->
        Logger.info("Discarding email to unknown address #{to} (from #{from})")
        :ok

      user ->
        Logger.info("Forwarding email from #{from} to #{user.email} (via #{to})")

        # TODO: handle parsing failures?
        :mimemail.decode(data)
        |> transmogrify(user.email)
        |> Mailer.deliver()
    end
  end

  # Take an email as parsed by mimemail, then convert it into a Swoosh.Email ready to send
  @spec transmogrify(:mimemail.mimetuple(), String.t()) :: Swoosh.Email.t()
  defp transmogrify(email, recipient_address) do
    email =
      new()
      |> build_email(email)
      |> Enricher.process()

    # Now we've put together our email, we modify make it clear it came from us
    recipient_name =
      if is_list(email.to) and Enum.empty?(email.to) do
        ""
      else
        [{recipient_name, _alias}] = email.to
        recipient_name
      end

    sender_name =
      if is_nil(email.reply_to) do
        ""
      else
        {sender_name, _sender_address} = email.reply_to
        sender_name
      end

    email
    |> from({sender_name <> @from_suffix, @from_email})
    |> Map.put(:to, [{recipient_name, recipient_address}])
  end

  @spec build_email(Swoosh.Email.t(), {String.t(), String.t(), [any()], any(), any()}) ::
          Swoosh.Email.t()
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

  defp build_email(email, {"multipart", "alternative", headers, _opts, parts})
       when is_list(parts) do
    parts
    |> Enum.reduce(email, fn part, acc -> build_email(acc, part) end)
    |> process_headers(headers)
  end

  @spec process_headers(Swoosh.Email.t(), [header_type]) :: Swoosh.Email.t()
  defp process_headers(email, headers) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(key), value} end)
    |> Enum.filter(fn {key, _value} -> Enum.member?(@allowed_headers, key) end)
    |> Enum.reduce(email, fn h, acc -> process_header(acc, h) end)
  end

  @spec process_header(Swoosh.Email.t(), {String.t(), any()}) :: Swoosh.Email.t()
  defp process_header(email, {"from", value}), do: reply_to(email, parse_address(value))
  defp process_header(email, {"subject", value}), do: subject(email, value)
  defp process_header(email, {"to", value}), do: to(email, parse_address(value))
  defp process_header(email, {key, value}), do: header(email, key, value)

  # Parses `email@example.com`, `Zero Cool <email@example.com>`, and `"Zero Cool" <email@example.com>"`.
  defp parse_address(address) do
    case Regex.run(~r/^(.*)<(.*@.*)>/, address) do
      nil ->
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
end
