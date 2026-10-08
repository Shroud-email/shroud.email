defmodule Shroud.Analytics do
  @moduledoc """
  Best-effort OpenPanel events. Only pseudonymous IDs and explicit event metadata
  cross this boundary; network work runs outside the lifecycle process.
  """

  @doc "Returns a stable analytics ID without exposing the database account ID."
  def profile_id(user_id) do
    key =
      Plug.Crypto.KeyGenerator.generate(
        ShroudWeb.Endpoint.config(:secret_key_base),
        "shroud.openpanel.profile-id.v1",
        cache: Plug.Crypto.Keys
      )

    :crypto.mac(:hmac, :sha256, key, to_string(user_id))
    |> Base.encode16(case: :lower)
  end

  def alias_created(email_alias) do
    capture(email_alias.user_id, "alias_created", %{
      custom_domain: not is_nil(email_alias.domain_id)
    })
  end

  def email_forwarded(user_id, true), do: capture(user_id, "email_forwarded", %{})
  def email_forwarded(_user_id, false), do: capture(nil, "email_forwarded", %{})
  def outgoing_email_sent, do: capture(nil, "outgoing_email_sent", %{})

  def signup(user_id, path) do
    # OpenPanel extracts properties.__query from __path during ingestion.
    capture(user_id, "signup", %{__path: path})
  end

  def paid_conversion(user_id, converted_at, source) when source in [:paddle, :lifetime_code],
    do: capture(user_id, "paid_conversion", %{source: Atom.to_string(source)}, converted_at)

  def identify(user_id), do: send_event("identify", %{profileId: profile_id(user_id)})

  defp capture(user_id, name, properties, occurred_at \\ DateTime.utc_now()) do
    payload = %{
      name: name,
      properties: Map.put(properties, :__timestamp, DateTime.to_iso8601(occurred_at))
    }

    payload =
      if is_nil(user_id), do: payload, else: Map.put(payload, :profileId, profile_id(user_id))

    send_event("track", payload)
  end

  defp send_event(type, payload) do
    config = Application.get_env(:shroud, :openpanel, [])

    if config[:enabled] and config[:client_secret] not in [nil, ""] do
      Task.Supervisor.start_child(Shroud.Analytics.Tasks, fn ->
        Req.post(
          url: String.trim_trailing(config[:api_url], "/") <> "/track",
          headers: [
            {"openpanel-client-id", config[:client_id]},
            {"openpanel-client-secret", config[:client_secret]},
            {"user-agent", "ShroudAnalytics/1.0"}
          ],
          json: %{type: type, payload: payload},
          retry: false,
          receive_timeout: 1_000,
          connect_options: [timeout: 1_000]
        )
      end)
    end

    :ok
  catch
    # Missing/stopping supervisor or saturation must not affect the operation.
    :exit, _reason -> :ok
  end
end
