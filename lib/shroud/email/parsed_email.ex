defmodule Shroud.Email.ParsedEmail do
  @moduledoc """
  Our internal representation of an email.
  """

  import Swoosh.Email
  require Logger

  defstruct [:swoosh_email, :parsed_html, removed_trackers: []]

  @type header_type :: {String.t(), String.t()}
  @type t :: %__MODULE__{
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

  @spec parse(:mimemail.mimetuple()) :: t
  def parse(mimemail_email) do
    swoosh_email = build_email(new(), mimemail_email)

    # TODO: maybe log some detailed errors if there's a parsing failure here
    parsed_html =
      case Floki.parse_document(swoosh_email.html_body) do
        {:ok, []} -> nil
        {:ok, parsed} -> parsed
        {:error, _error} -> nil
      end

    %__MODULE__{
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
