defmodule Shroud.Email.EncodedWord do
  @moduledoc """
  Parse FFC2047 encoded words.
  """

  @spec decode(String.t()) :: String.t()
  def decode(text) do
    parse_encoded_word(text)
  end

  defp parse_encoded_word(""), do: ""

  defp parse_encoded_word(<<"=?", value::binary>>) do
    [_charset, encoding, encoded_string, <<"=", remainder::binary>>] =
      String.split(value, "?", parts: 4)

    decoded_string =
      case String.upcase(encoding) do
        "Q" ->
          Mail.Encoders.QuotedPrintable.decode(encoded_string)

        "B" ->
          Mail.Encoders.Base64.decode(encoded_string)
      end

    decoded_string <> parse_encoded_word(remainder)
  end

  defp parse_encoded_word(<<char::utf8, rest::binary>>),
    do: <<char::utf8, parse_encoded_word(rest)::binary>>
end
