defmodule ShroudWeb.Layouts do
  use ShroudWeb, :html

  @doc """
  The base URL of the configured Chatwoot server, or nil when the widget
  is disabled (e.g. self-hosted deployments that don't set
  CHATWOOT_BASE_URL). All widget markup/JS is gated on this being set.
  """
  def chatwoot_base_url do
    case Application.get_env(:shroud, :chatwoot_base_url) do
      url when url in [nil, ""] -> nil
      url -> url
    end
  end

  @doc """
  Generates the HMAC-SHA256 identifier hash Chatwoot uses to validate the
  identity of an authenticated user. Returns nil when no user is signed in
  or no HMAC token is configured, in which case the widget falls back to
  anonymous mode.
  """
  def chatwoot_identifier_hash(nil), do: nil

  def chatwoot_identifier_hash(%Shroud.Accounts.User{email: email}) do
    case Application.get_env(:shroud, :chatwoot_hmac_token) do
      token when is_binary(token) and token != "" ->
        :crypto.mac(:hmac, :sha256, token, email)
        |> Base.encode16(case: :lower)

      _ ->
        nil
    end
  end

  embed_templates("layouts/*")
end
