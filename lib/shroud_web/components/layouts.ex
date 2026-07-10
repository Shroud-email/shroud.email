defmodule ShroudWeb.Layouts do
  use ShroudWeb, :html

  def active_class(conn, path, default_class, active_class \\ "active") do
    if path == Phoenix.Controller.current_path(conn) do
      default_class <> " " <> active_class
    else
      default_class
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
