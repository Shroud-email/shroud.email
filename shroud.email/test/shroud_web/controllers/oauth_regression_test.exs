defmodule ShroudWeb.OAuthRegressionTest do
  use ShroudWeb.ConnCase, async: false
  import Shroud.OAuthFixtures
  alias Shroud.{Accounts, OAuth, Repo}

  setup do
    %{user: confirmed_user()}
  end

  test "connection navigation and browser connection pages are available to flagged users", %{
    user: user
  } do
    {params, _} = authorization_params(["aliases:read"])

    for {path, params, selector} <- [
          {"/settings/security", %{}, "#manage-connections"},
          {"/oauth/authorize", params, "header a[href='/settings/connections']"}
        ] do
      document =
        build_conn()
        |> log_in_user(user)
        |> get(path, params)
        |> html_response(200)
        |> Floki.parse_document!()

      links = Floki.find(document, selector)
      assert links != []
    end

    assert build_conn() |> log_in_user(user) |> get("/settings/connections") |> response(200)
  end

  test "the MCP flag gates MCP consent but not connection management", %{user: user} do
    {params, _} = authorization_params(["aliases:read"])
    FunWithFlags.disable(:chatgpt_integration, for_actor: user)

    conn = build_conn() |> log_in_user(user)
    assert conn |> get("/oauth/authorize", params) |> response(404)
    assert conn |> post("/oauth/authorize", %{}) |> response(404)
    assert conn |> get("/settings/connections") |> response(200)

    document = conn |> get("/settings/security") |> html_response(200) |> Floki.parse_document!()
    assert Floki.find(document, "#manage-connections") != []
  end

  test "callbacks append response fields without changing registered query bytes", %{user: user} do
    for query <- [nil, "", "tag=first&tag=second&encoded=%2f%20&bare&empty="],
        decision <- ["allow", "deny"] do
      callback = "https://client.example/callback" <> if(query == nil, do: "", else: "?" <> query)
      {params, _} = authorization_params(["aliases:read"], callback)
      params = %{params | "state" => "state & + /"}

      html =
        build_conn() |> log_in_user(user) |> get("/oauth/authorize", params) |> html_response(200)

      approval =
        html
        |> Floki.parse_document!()
        |> Floki.find("input[name=approval]")
        |> Floki.attribute("value")
        |> hd()

      location =
        build_conn()
        |> log_in_user(user)
        |> post("/oauth/authorize", %{approval: approval, decision: decision})
        |> redirected_to()
        |> URI.parse()

      response_query =
        if query in [nil, ""] do
          location.query
        else
          assert String.starts_with?(location.query, query <> "&")
          String.replace_prefix(location.query, query <> "&", "")
        end

      response = URI.decode_query(response_query)
      assert response["state"] == params["state"]
      assert response["iss"] == OAuth.issuer()

      if decision == "allow",
        do: assert(response["code"] != nil),
        else: assert(response["error"] == "access_denied")
    end
  end

  test "consent keeps its isolated layout and settings use the account theme", %{
    user: user
  } do
    {params, _} = authorization_params(["aliases:read"])

    for theme <- [:dark, :light, :system] do
      user =
        Accounts.User
        |> Repo.get!(user.id)
        |> Accounts.User.theme_changeset(%{theme: theme})
        |> Repo.update!()

      for {path, params} <- [{"/settings/connections", %{}}, {"/oauth/authorize", params}] do
        conn = build_conn() |> log_in_user(user) |> get(path, params)
        document = conn |> html_response(200) |> Floki.parse_document!()
        assert Floki.attribute(document, "meta[name=theme]", "content") == [to_string(theme)]

        assert Floki.find(document, "meta[name=csrf-token]") != []
        assert Floki.attribute(document, "body", "class") |> hd() =~ "dark:bg-gray-900"

        if path == "/oauth/authorize" do
          assert Floki.attribute(document, "html", "class") ==
                   if(theme == :dark, do: ["dark"], else: [""])

          assert Floki.attribute(document, "script", "src") == ["/assets/app.js"]
          assert get_resp_header(conn, "cache-control") == ["no-store"]
          assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
          refute conn.resp_body =~ "chatwoot"
          refute conn.resp_body =~ "betterstack"
        else
          assert Floki.find(document, "#settings-nav-security[aria-current=page]") != []
          assert Floki.find(document, "#connections[phx-update=stream]") != []
        end
      end
    end
  end
end
