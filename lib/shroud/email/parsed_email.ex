defmodule Shroud.Email.ParsedEmail do
  @moduledoc """
  Our internal representation of an email.
  """

  import Swoosh.Email
  require Logger

  @enforce_keys [:raw_email]
  defstruct [:raw_email, :swoosh_email, :parsed_html, removed_trackers: []]

  @type header_type :: {String.t(), String.t()}
  @type t :: %__MODULE__{
          raw_email: String.t(),
          swoosh_email: Swoosh.Email.t(),
          parsed_html: Floki.html_tree(),
          removed_trackers: [String.t()]
        }

  @allowed_headers [
    "from",
    "to",
    "reply-to",
    "subject",
    "date",
    "delivered-to"
  ]

  @spec parse(String.t()) :: t
  def parse(raw_email) do
    # TODO: handle parsing failures from mimemail?
    parsed_email = :mimemail.decode(raw_email)
    swoosh_email = build_email(new(), parsed_email)

    # TODO: maybe log some detailed errors if there's a parsing failure here
    parsed_html =
      case Floki.parse_document(swoosh_email.html_body) do
        {:ok, []} -> nil
        {:ok, parsed} -> parsed
        {:error, _error} -> nil
      end

    %__MODULE__{
      raw_email: raw_email,
      swoosh_email: swoosh_email,
      parsed_html: parsed_html
    }
  end

  @spec build_email(Swoosh.Email.t(), :mimemail.mimetuple()) ::
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
