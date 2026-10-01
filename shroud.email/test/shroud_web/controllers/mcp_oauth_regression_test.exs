defmodule ShroudWeb.McpOAuthRegressionTest do
  use ShroudWeb.ConnCase, async: false
  import Shroud.McpFixtures
  alias Shroud.{Accounts, Mcp, Repo}

  setup do
    configure_clients()
    %{user: confirmed_user()}
  end

  test "callbacks append response fields without changing registered query bytes", %{user: user} do
    for query <- [nil, "", "tag=first&tag=second&encoded=%2f%20&bare&empty="],
        decision <- ["allow", "deny"] do
      callback = "https://client.example/callback" <> if(query == nil, do: "", else: "?" <> query)
      clients = Application.fetch_env!(:shroud, :mcp_clients)

      Application.put_env(
        :shroud,
        :mcp_clients,
        put_in(clients, ["test-client", "redirect_uris"], [callback])
      )

      {params, _} = authorization_params(["aliases:read"])
      params = %{params | "redirect_uri" => callback, "state" => "state & + /"}

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
      assert response["iss"] == Mcp.issuer()

      if decision == "allow",
        do: assert(response["code"] != nil),
        else: assert(response["error"] == "access_denied")
    end
  end

  test "both browser pages keep the pipeline layout and initialize the account theme", %{
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

        assert Floki.attribute(document, "html", "class") ==
                 if(theme == :dark, do: ["dark"], else: [""])

        assert Floki.attribute(document, "script", "src") == ["/assets/app.js"]
        assert Floki.find(document, "meta[name=csrf-token]") != []
        assert Floki.attribute(document, "body", "class") |> hd() =~ "dark:bg-gray-900"
        assert get_resp_header(conn, "cache-control") == ["no-store"]
        assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
        refute conn.resp_body =~ "chatwoot"
        refute conn.resp_body =~ "betterstack"
      end
    end
  end
end
