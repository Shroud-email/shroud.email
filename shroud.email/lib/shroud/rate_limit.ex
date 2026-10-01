defmodule Shroud.RateLimit do
  @moduledoc """
  Single-node, in-memory rate limiting. Allowances reset when the backend restarts.
  """

  use Hammer, backend: :atomic

  def check(policy, actor) do
    {scale, limit} = policy(policy)
    hit({policy, actor}, scale, limit)
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  def policy(:http), do: {:timer.minutes(1), 600}
  def policy(:sign_in), do: {:timer.minutes(1), 10}
  def policy(:second_factor), do: {:timer.minutes(1), 5}
  def policy(:account_email), do: {:timer.minutes(15), 5}
  def policy(:credentials), do: {:timer.minutes(15), 5}
  def policy(:api), do: {:timer.minutes(1), 120}
  def policy(:image_proxy), do: {:timer.minutes(1), 120}
  def policy(:billing), do: {:timer.minutes(1), 10}
  def policy(:events), do: {:timer.minutes(1), 120}
  def policy(:passkey_challenge), do: {:timer.minutes(1), 10}
  def policy({:security, _group}), do: {:timer.minutes(1), 5}
end
