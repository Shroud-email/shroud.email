defmodule ShroudWeb.MobileAssociationControllerTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint ShroudWeb.Endpoint

  setup do
    previous = Application.fetch_env(:shroud, :mobile_associations)
    Application.delete_env(:shroud, :mobile_associations)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:shroud, :mobile_associations, value)
        :error -> Application.delete_env(:shroud, :mobile_associations)
      end
    end)

    :ok
  end

  test "missing identities return uncached JSON 404s independently" do
    for action <- [:apple, :android] do
      conn = request(action)
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert get_resp_header(conn, "location") == []
    end
  end

  test "Apple association advertises only supported paths and the reserved callback" do
    Application.put_env(:shroud, :mobile_associations, apple_team_id: "TESTTEAM01")
    conn = request(:apple)

    assert json_response(conn, 200) == %{
             "applinks" => %{
               "apps" => [],
               "details" => [
                 %{
                   "appID" => "TESTTEAM01.email.shroud.app",
                   "paths" => ["/", "/explore", "/oauth/callback"]
                 }
               ]
             }
           }

    assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    assert get_resp_header(conn, "location") == []
    assert request(:android).status == 404
  end

  test "Android association supports multiple signing certificates" do
    fingerprints = [
      Enum.join(List.duplicate("AB", 32), ":"),
      Enum.join(List.duplicate("CD", 32), ":")
    ]

    Application.put_env(:shroud, :mobile_associations,
      android_sha256_cert_fingerprints: fingerprints
    )

    conn = request(:android)

    assert json_response(conn, 200) == [
             %{
               "relation" => ["delegate_permission/common.handle_all_urls"],
               "target" => %{
                 "namespace" => "android_app",
                 "package_name" => "email.shroud.app",
                 "sha256_cert_fingerprints" => fingerprints
               }
             }
           ]

    assert get_resp_header(conn, "cache-control") == ["public, max-age=3600"]
    assert get_resp_header(conn, "location") == []
    assert request(:apple).status == 404
  end

  test "malformed identities do not advertise associations" do
    for team <- ["", "invalid", "TESTTEAM01.other", 123] do
      Application.put_env(:shroud, :mobile_associations, apple_team_id: team)
      assert request(:apple).status == 404
    end

    for fingerprints <- [
          [],
          "AB:CD",
          ["AB:CD"],
          [nil],
          [Enum.join(List.duplicate("AB", 32), ":"), "invalid"]
        ] do
      Application.put_env(:shroud, :mobile_associations,
        android_sha256_cert_fingerprints: fingerprints
      )

      assert request(:android).status == 404
    end
  end

  defp request(action) do
    path =
      if action == :apple,
        do: "/.well-known/apple-app-site-association",
        else: "/.well-known/assetlinks.json"

    build_conn() |> get(path)
  end
end
