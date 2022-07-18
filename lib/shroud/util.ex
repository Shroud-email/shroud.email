defmodule Shroud.Util do
  @spec uri_encode_map!(any()) :: String.t()
  def uri_encode_map!(data) do
    data
    |> Jason.encode!()
    |> Base.encode64()
    |> URI.encode()
  end

  @spec uri_decode_map(data: String.t()) :: {:ok, any()} | :error
  def uri_decode_map(data) do
    data = URI.decode(data)

    with {:ok, json} <- Base.decode64(data, ignore: :whitespace, padding: false),
         {:ok, map} <- Jason.decode(json) do
      {:ok, map}
    else
      {:error, _error} -> :error
      :error -> :error
    end
  end

  @spec past?(NaiveDateTime.t()) :: boolean
  def past?(datetime) do
    now = NaiveDateTime.utc_now()
    NaiveDateTime.compare(datetime, now) == :lt
  end

  @spec email_domain() :: String.t()
  def email_domain() do
    Application.get_env(:shroud, :email_domain)
  end

  @spec crlf_to_lf(String.t() | nil) :: String.t() | nil
  def crlf_to_lf(nil) do
    nil
  end

  def crlf_to_lf(string) do
    string
    |> String.replace(~r/\r\n/, "\n")
    |> String.trim()
  end

  @spec lf_to_crlf(String.t()) :: String.t()
  def lf_to_crlf(string) do
    string
    |> String.replace("\n", "\r\n")
    |> String.trim()
  end

  @spec extract_email_parts(String.t()) :: {String.t(), String.t()}
  @doc ~S"""
  Extracts the local part and domain from an email address.

  ## Examples

      iex> Shroud.Util.extract_email_parts("user@domain.com")
      {"user", "domain.com"}

      iex> Shroud.Util.extract_email_parts("\"complex@address\"@domain.co.uk")
      {"\"complex@address\"", "domain.co.uk"}
  """
  def extract_email_parts(email) do
    [domain | locals] =
      email
      |> String.reverse()
      |> String.split("@")
      |> Enum.map(&String.reverse/1)

    local_part = locals |> Enum.reverse() |> Enum.join("@")
    {local_part, domain}
  end
end
