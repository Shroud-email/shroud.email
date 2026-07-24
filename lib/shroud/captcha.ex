defmodule Shroud.Captcha do
  @moduledoc """
  Boundary module for the optional Cap CAPTCHA integration.

  Cap is enabled only when all three of CAP_INSTANCE_URL, CAP_SITE_KEY,
  and CAP_SECRET_KEY are configured. When disabled, every function here
  is a safe no-op: `enabled?/0` is false, `widget_endpoint/0` is nil, and
  the `VerifyCaptcha` plug short-circuits.
  """

  @doc """
  True iff all three Cap env vars are configured. This is the single gate
  the rest of the app checks to decide whether Cap is active.
  """
  @spec enabled? :: boolean
  def enabled? do
    present?(instance_url()) and present?(site_key()) and present?(secret_key())
  end

  @doc """
  The widget's `data-cap-api-endpoint` value: the Cap instance URL plus the
  site key, with a guaranteed trailing slash. Returns nil when Cap is
  disabled (so the widget is not rendered at all).
  """
  @spec widget_endpoint :: String.t() | nil
  def widget_endpoint do
    if enabled?() do
      "#{String.trim_trailing(instance_url(), "/")}/#{site_key()}/"
    else
      nil
    end
  end

  @doc """
  Verify a Cap token against the Standalone `/siteverify` endpoint.

  Returns `:ok` on success, or one of:
    * `{:error, :missing_token}` — token was nil or empty
    * `{:error, :verification_failed}` — Cap rejected the token
    * `{:error, :network_error}` — the HTTP call failed or response was
      unparseable. Fail-closed: callers should reject the request.
  """
  @spec verify(String.t() | nil) :: :ok | {:error, atom}
  def verify(nil), do: {:error, :missing_token}
  def verify(""), do: {:error, :missing_token}

  def verify(token) when is_binary(token) do
    if enabled?() do
      verify_token(token)
    else
      {:error, :verification_failed}
    end
  end

  # Fail-closed catch-all: a non-binary token (e.g. a list or map) returns
  # verification_failed rather than crashing on String.trim_trailing(nil, "/")
  # in siteverify_url/0.
  def verify(_), do: {:error, :verification_failed}

  defp verify_token(token) do
    body = %{"secret" => secret_key(), "response" => token}

    case req_post(siteverify_url(), body) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %Req.Response{body: %{"success" => _}}} ->
        {:error, :verification_failed}

      {:ok, %Req.Response{}} ->
        {:error, :verification_failed}

      {:error, _reason} ->
        {:error, :network_error}
    end
  end

  defp req_post(url, body) do
    options =
      [
        url: url,
        method: :post,
        json: body,
        # Bounded so a slow/unreachable Cap instance cannot stall form
        # submissions. 3s to establish the connection, 5s to read the
        # response. Both map to Finch via Req (see deps/req/lib/req/steps.ex).
        connect_options: [timeout: 3_000],
        receive_timeout: 5_000
      ]
      |> Keyword.merge(Application.get_env(:shroud, :cap_req_options, []))

    Req.request(options)
  end

  defp siteverify_url do
    "#{String.trim_trailing(instance_url(), "/")}/#{site_key()}/siteverify"
  end

  defp instance_url, do: Application.get_env(:shroud, :cap_instance_url)
  defp site_key, do: Application.get_env(:shroud, :cap_site_key)
  defp secret_key, do: Application.get_env(:shroud, :cap_secret_key)

  # True only for a binary that is non-empty after trimming. Treats nil,
  # empty strings, and whitespace-only strings (the values example.env
  # produces for unset vars) all as "not configured".
  defp present?(value) when is_binary(value) do
    String.trim(value) != ""
  end

  defp present?(_), do: false
end
