defmodule Shroud.DateTime do
  @behaviour Shroud.DateTimeBehaviour

  def utc_now_unix() do
    DateTime.utc_now() |> DateTime.to_unix()
  end
end
