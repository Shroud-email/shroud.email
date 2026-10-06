defmodule Shroud.Email.InboxEmail do
  @moduledoc "Reads inbox MIME messages without rewriting attachment payloads."
  alias Shroud.Email.ParsedEmail

  def parse(data, sender, recipient) do
    message = Mailex.parse!(data)
    {body_message, attachments} = extract(data, message)
    email = ParsedEmail.parse(body_message, sender, recipient).swoosh_email
    %{email | attachments: attachments}
  end

  # Mailex supplies decoded metadata. Raw MIME parts supply attachment bytes,
  # before charset conversion, line-ending normalization or embedded-email parsing.
  defp extract(raw, message) do
    {_headers, body} = :mimemail.parse_headers(raw)

    cond do
      attachment?(message) ->
        attachment =
          Swoosh.Attachment.new({:data, decode(body, message.encoding)},
            filename: message.filename || "attachment",
            content_type: "#{message.content_type.type}/#{message.content_type.subtype}"
          )

        {%{
           message
           | body: "",
             parts: nil,
             content_type: %{type: "application", subtype: "octet-stream", params: %{}}
         }, [attachment]}

      message.content_type.type == "multipart" and is_list(message.parts) ->
        boundary = Map.fetch!(message.content_type.params, "boundary")

        delimiter = ~r/(?:\A|\r?\n)--#{Regex.escape(boundary)}(?:--)?[ \t]*(?:\r?\n|\z)/

        raw_parts =
          delimiter |> Regex.split(body) |> Enum.drop(1) |> Enum.take(length(message.parts))

        extracted = Enum.zip_with(raw_parts, message.parts, &extract/2)

        {%{message | parts: Enum.map(extracted, &elem(&1, 0))},
         Enum.flat_map(extracted, &elem(&1, 1))}

      true ->
        {%{message | parts: nil}, []}
    end
  end

  defp attachment?(message) do
    message.disposition_type == "attachment" or not is_nil(message.filename) or
      (message.disposition_type == "inline" and message.content_type.type == "message") or
      (message.content_type.type not in ["text", "multipart", "message"] and
         is_binary(message.body))
  end

  defp decode(body, "base64"), do: Base.decode64!(body, ignore: :whitespace)
  defp decode(body, "quoted-printable"), do: :mimemail.decode_quoted_printable(body)
  defp decode(body, _encoding), do: body
end
