defmodule Shroud.Email.ParsedEmail do
  @moduledoc """
  Our internal representation of an email.
  """

  import Swoosh.Email
  require Logger

  defstruct [:from, :to, :swoosh_email, :parsed_html, removed_trackers: []]

  @type header_type :: {String.t(), String.t()}
  @type t :: %__MODULE__{
          from: String.t(),
          to: String.t(),
          swoosh_email: Swoosh.Email.t(),
          parsed_html: Floki.html_tree(),
          removed_trackers: [String.t()]
        }

  @allowed_headers [
    "from",
    "subject",
    "to",
    "reply-to",
    "date",
    "delivered-to"
  ]

  @spec parse(:mimemail.mimetuple() | Mailex.Message.t(), String.t(), String.t()) :: t
  def parse(%Mailex.Message{} = mailex_msg, from, to) do
    swoosh_email = build_email_from_mailex(new(), mailex_msg)

    parsed_html =
      if swoosh_email.html_body do
        case Floki.parse_document(swoosh_email.html_body) do
          {:ok, []} -> nil
          {:ok, parsed} -> parsed
          {:error, _error} -> nil
        end
      else
        nil
      end

    %__MODULE__{
      from: from,
      to: to,
      swoosh_email: swoosh_email,
      parsed_html: parsed_html
    }
  end

  def parse(mimemail_email, from, to) do
    swoosh_email = build_email(new(), mimemail_email)

    parsed_html =
      if swoosh_email.html_body do
        case Floki.parse_document(swoosh_email.html_body) do
          {:ok, []} -> nil
          {:ok, parsed} -> parsed
          {:error, _error} -> nil
        end
      else
        nil
      end

    %__MODULE__{
      from: from,
      to: to,
      swoosh_email: swoosh_email,
      parsed_html: parsed_html
    }
  end

  # HTML
  @spec build_email(Swoosh.Email.t(), :mimemail.mimetuple()) ::
          Swoosh.Email.t()
  defp build_email(email, {"text", "html", headers, _opts, body}) do
    email
    |> html_body(body)
    |> process_headers(headers)
  end

  # Plaintext
  defp build_email(email, {"text", "plain", headers, _opts, body}) do
    email
    |> text_body(body)
    |> process_headers(headers)
  end

  # HTML + plaintext
  defp build_email(email, {"multipart", "alternative", headers, _opts, parts})
       when is_list(parts) do
    parts
    |> Enum.reduce(email, fn part, acc -> build_email(acc, part) end)
    |> process_headers(headers)
  end

  # Email with attachment(s)
  defp build_email(email, {"multipart", "mixed", headers, _opts, parts})
       when is_list(parts) do
    parts
    |> Enum.reduce(email, fn part, acc -> build_email(acc, part) end)
    |> process_headers(headers)
  end

  # Email with inline attachment(s)
  defp build_email(email, {"multipart", "related", headers, _opts, parts}) when is_list(parts) do
    parts
    |> Enum.reduce(email, fn part, acc -> build_email(acc, part) end)
    |> process_headers(headers)
  end

  defp build_email(email, {"message", "rfc822", _headers, _opts, _body}) do
    # We're in a bounce report, and this section contains the original email.
    # We don't want that -- we're interested in the bounce report.
    # So we do nothing!
    email
  end

  # Fallback
  defp build_email(email, {_mime, _type, headers, _opts, parts}) when is_list(parts) do
    parts
    |> Enum.reduce(email, fn part, acc -> build_email(acc, part) end)
    |> process_headers(headers)
  end

  # Attachment
  defp build_email(
         email,
         {_mime_type, _mime_subtype, headers, opts, data}
       )
       when is_binary(data) do
    {_key, name} =
      opts
      |> Map.get(:content_type_params, [])
      |> Enum.find({nil, nil}, fn {key, _value} -> String.downcase(key) == "name" end)

    {_key, cid} =
      headers
      |> Enum.find({nil, nil}, fn {key, _value} -> String.downcase(key) == "content-id" end)

    cid =
      if not is_nil(cid) do
        cid
        |> String.replace_leading("<", "")
        |> String.replace_trailing(">", "")
      end

    process_attachment(email, data, name: name, cid: cid)
  end

  @spec process_headers(Swoosh.Email.t(), [header_type]) :: Swoosh.Email.t()
  defp process_headers(email, headers) do
    headers
    |> Enum.map(fn {key, value} -> {String.downcase(key), value} end)
    |> Enum.filter(fn {key, _value} -> Enum.member?(@allowed_headers, key) end)
    |> Enum.reduce(email, fn h, acc -> process_header(acc, h) end)
  end

  @spec process_header(Swoosh.Email.t(), {String.t(), any()}) :: Swoosh.Email.t()
  defp process_header(email, {"from", value}), do: from(email, parse_address(value))
  defp process_header(email, {"subject", value}), do: subject(email, value)
  defp process_header(email, {"to", value}), do: to(email, parse_address(value))
  defp process_header(email, {"reply-to", value}), do: reply_to(email, parse_address(value))
  defp process_header(email, {key, value}), do: header(email, key, value)

  @spec process_attachment(Swoosh.Email.t(), binary(), Keyword.t()) :: Swoosh.Email.t()
  defp process_attachment(email, data, options) when is_binary(data) do
    is_inline = Keyword.get(options, :inline, false)
    cid = Keyword.get(options, :cid, nil)

    name =
      options
      |> Keyword.get(:name)
      |> Kernel.||("attachment")

    mime_type =
      name
      |> Path.extname()
      |> String.replace(".", "")
      |> MIME.type()

    type = if is_inline, do: :inline, else: :attachment

    swoosh_attachment =
      Swoosh.Attachment.new(
        {:data, data},
        filename: name,
        content_type: mime_type,
        type: type,
        cid: cid
      )

    attachment(email, swoosh_attachment)
  end

  # Parses `email@example.com`, `Zero Cool <email@example.com>`, and `"Zero Cool" <email@example.com>"`.
  defp parse_address(address) do
    case Regex.run(~r/^(.*)<(.*@.*)>/, address) do
      nil ->
        sanitized = sanitize_email_address(address)
        {sanitized, sanitized}

      [_string, name_part, address_part] ->
        {trim_quotes_and_whitespace(name_part), sanitize_email_address(String.trim(address_part))}

      _other ->
        Logger.warning("Failed to parse address: #{address}")
        {nil, sanitize_email_address(address)}
    end
  end

  # Sanitizes malformed email addresses by:
  # 1. Removing spaces from the local part
  # 2. Stripping invalid bracket notation from domains (e.g., [domain] -> domain)
  # This handles (likely spam) emails that have invalid addresses like "foo bar@example.com"
  # or "user@[domain]" which would otherwise cause gen_smtp/mimemail to crash during encoding.
  # It's not great that we're modifying the email address, but it's better than crashing.
  defp sanitize_email_address(address) do
    case String.split(address, "@", parts: 2) do
      [local_part, domain] ->
        sanitized_local = String.replace(local_part, ~r/\s+/, "")
        sanitized_domain = sanitize_domain(domain)
        "#{sanitized_local}@#{sanitized_domain}"

      _ ->
        # No @ sign found, just remove spaces
        String.replace(address, ~r/\s+/, "")
    end
  end

  # Sanitizes the domain part of an email address.
  # RFC 5321 allows IP address literals in brackets like [192.168.1.1] or [IPv6:...],
  # but some spam emails use invalid bracket notation like [domain].
  # This strips brackets from invalid bracket notation while preserving valid IP literals.
  defp sanitize_domain(domain) do
    case Regex.run(~r/^\[(.+)\]$/, domain) do
      [_full, content] ->
        if valid_ip_literal?(content) do
          # Valid IP literal, keep the brackets
          domain
        else
          # Invalid bracket notation, strip the brackets
          content
        end

      nil ->
        # No brackets, return as-is
        domain
    end
  end

  defp valid_ip_literal?(content) do
    # Check for IPv4
    case :inet.parse_address(String.to_charlist(content)) do
      {:ok, _} ->
        true

      {:error, _} ->
        # Check for IPv6 with "IPv6:" prefix (RFC 5321)
        case content do
          "IPv6:" <> ipv6 ->
            case :inet.parse_address(String.to_charlist(ipv6)) do
              {:ok, {_, _, _, _, _, _, _, _}} -> true
              _ -> false
            end

          _ ->
            false
        end
    end
  end

  defp trim_quotes_and_whitespace(str) do
    str
    |> String.replace(~r/^['"\s\\]+/, "")
    |> String.replace(~r/['"\s\\]+$/, "")
  end

  # Mailex support

  @spec build_email_from_mailex(Swoosh.Email.t(), Mailex.Message.t()) :: Swoosh.Email.t()
  defp build_email_from_mailex(email, %Mailex.Message{} = msg) do
    email
    |> process_mailex_content(msg)
    |> process_mailex_headers(msg.headers)
  end

  defp build_email_from_mailex_part(email, %Mailex.Message{} = msg) do
    process_mailex_content_part(email, msg)
  end

  defp process_mailex_content(email, %Mailex.Message{parts: parts})
       when is_list(parts) and parts != [] do
    Enum.reduce(parts, email, fn part, acc -> build_email_from_mailex_part(acc, part) end)
  end

  defp process_mailex_content(
         email,
         %Mailex.Message{content_type: %{type: "text", subtype: "html"}} = msg
       ) do
    html_body(email, msg.body || "")
  end

  defp process_mailex_content(
         email,
         %Mailex.Message{content_type: %{type: "text", subtype: "plain"}} = msg
       ) do
    text_body(email, msg.body || "")
  end

  defp process_mailex_content(email, %Mailex.Message{
         content_type: %{type: "message", subtype: "rfc822"}
       }) do
    email
  end

  defp process_mailex_content(email, %Mailex.Message{} = msg) do
    if mailex_attachment?(msg) do
      process_mailex_attachment(email, msg)
    else
      email
    end
  end

  defp process_mailex_content_part(email, %Mailex.Message{
         content_type: %{type: "message", subtype: "rfc822"}
       }) do
    email
  end

  defp process_mailex_content_part(email, %Mailex.Message{
         content_type: %{type: "message", subtype: "delivery-status"}
       }) do
    email
  end

  defp process_mailex_content_part(email, %Mailex.Message{parts: parts})
       when is_list(parts) and parts != [] do
    Enum.reduce(parts, email, fn part, acc -> build_email_from_mailex_part(acc, part) end)
  end

  defp process_mailex_content_part(
         email,
         %Mailex.Message{content_type: %{type: "text", subtype: "html"}} = msg
       ) do
    html_body(email, msg.body || "")
  end

  defp process_mailex_content_part(
         email,
         %Mailex.Message{content_type: %{type: "text", subtype: "plain"}} = msg
       ) do
    text_body(email, msg.body || "")
  end

  defp process_mailex_content_part(email, %Mailex.Message{} = msg) do
    if mailex_attachment?(msg) do
      process_mailex_attachment(email, msg)
    else
      email
    end
  end

  defp mailex_attachment?(%Mailex.Message{} = msg) do
    msg.disposition_type in ["attachment", "inline"] or
      not is_nil(msg.filename) or
      (msg.content_type.type != "text" and msg.content_type.type != "multipart" and
         is_binary(msg.body) and msg.body != "")
  end

  defp process_mailex_attachment(email, %Mailex.Message{} = msg) do
    cid = normalize_cid(msg.content_id)
    is_inline = msg.disposition_type == "inline" or not is_nil(cid)

    name = msg.filename || Map.get(msg.content_type.params, "name") || "attachment"

    mime_type = "#{msg.content_type.type}/#{msg.content_type.subtype}"

    type = if is_inline, do: :inline, else: :attachment

    swoosh_attachment =
      Swoosh.Attachment.new(
        {:data, msg.body || ""},
        filename: name,
        content_type: mime_type,
        type: type,
        cid: cid
      )

    attachment(email, swoosh_attachment)
  end

  defp normalize_cid(nil), do: nil

  defp normalize_cid(cid) do
    cid
    |> String.replace_leading("<", "")
    |> String.replace_trailing(">", "")
  end

  defp process_mailex_headers(email, headers) when is_map(headers) do
    headers
    |> Enum.filter(fn {key, _value} -> Enum.member?(@allowed_headers, key) end)
    |> Enum.reduce(email, fn {key, value}, acc ->
      value_str = mailex_header_value_to_string(value)

      if String.trim(value_str) == "" do
        acc
      else
        process_header(acc, {key, value_str})
      end
    end)
  end

  defp mailex_header_value_to_string(value) when is_binary(value), do: value
  defp mailex_header_value_to_string([head | _]), do: mailex_header_value_to_string(head)
  defp mailex_header_value_to_string(_), do: ""
end
