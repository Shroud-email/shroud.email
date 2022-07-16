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
end
