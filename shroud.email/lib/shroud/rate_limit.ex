defmodule Shroud.RateLimit do
  @moduledoc """
  Single-node, in-memory rate limiting. Allowances reset on application restart.
  """

  use Hammer, backend: :atomic
end
