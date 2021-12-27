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
end
