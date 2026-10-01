defmodule Shroud.Mcp.Cache do
  @moduledoc "Keep Boruta's reads authoritative across database transactions."
  def get(_key), do: {:ok, nil}
  def put(_key, _value, _opts \\ []), do: :ok
  def delete(_key), do: :ok
end
