defmodule ShroudWeb.MobileAssociationController do
  use ShroudWeb, :controller

  @bundle_id "email.shroud.app"
  @paths ["/", "/explore", "/oauth/callback"]

  def apple(conn, _params) do
    team_id = config()[:apple_team_id]

    if is_binary(team_id) and Regex.match?(~r/\A[A-Z0-9]{10}\z/, team_id) do
      association(conn, %{
        applinks: %{apps: [], details: [%{appID: "#{team_id}.#{@bundle_id}", paths: @paths}]}
      })
    else
      unavailable(conn)
    end
  end

  def android(conn, _params) do
    fingerprints = config()[:android_sha256_cert_fingerprints]

    if valid_fingerprints?(fingerprints) do
      association(conn, [
        %{
          relation: ["delegate_permission/common.handle_all_urls"],
          target: %{
            namespace: "android_app",
            package_name: @bundle_id,
            sha256_cert_fingerprints: fingerprints
          }
        }
      ])
    else
      unavailable(conn)
    end
  end

  defp config, do: Application.get_env(:shroud, :mobile_associations, [])

  defp valid_fingerprints?([_ | _] = fingerprints) do
    Enum.all?(fingerprints, fn fingerprint ->
      is_binary(fingerprint) and
        Regex.match?(~r/\A(?:[0-9A-F]{2}:){31}[0-9A-F]{2}\z/, fingerprint)
    end)
  end

  defp valid_fingerprints?(_), do: false

  defp association(conn, body) do
    conn
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> json(body)
  end

  defp unavailable(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:not_found)
    |> json(%{error: "not_found"})
  end
end
