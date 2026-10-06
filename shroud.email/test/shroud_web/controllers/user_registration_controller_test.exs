defmodule ShroudWeb.UserRegistrationControllerTest do
  # Mutates global Application env (cap_*) via enable_cap/disable_cap in the
  # "Cap enabled" describe block below; must run serially to stay isolation-safe.
  use ShroudWeb.ConnCase, async: false

  import Shroud.AccountsFixtures
  import ShroudWeb.CaptchaHelpers

  test "campaign survives signup form, invalid submission and account creation", %{conn: conn} do
    previous = Application.get_env(:shroud, :openpanel)
    on_exit(fn -> Application.put_env(:shroud, :openpanel, previous) end)
    bypass = Bypass.open()
    owner = self()

    Application.put_env(:shroud, :openpanel,
      enabled: true,
      client_id: "test",
      client_secret: "test",
      api_url: "http://localhost:#{bypass.port}/api"
    )

    Bypass.expect(bypass, "POST", "/api/track", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(owner, {:signup_event, Jason.decode!(body)})
      Plug.Conn.resp(conn, 200, "{}")
    end)

    campaign = %{
      "utm_source" => "newsletter",
      "utm_medium" => "email",
      "utm_campaign" => "autumn & winter",
      "utm_term" => "privacy",
      "utm_content" => "footer",
      "utm_id" => "campaign-42",
      "utm_source_platform" => "loops",
      "utm_creative_format" => "text",
      "utm_marketing_tactic" => "prospecting",
      "gclid" => "google-click",
      "fbclid" => "meta-click",
      "custom_tag" => String.duplicate("é", 201),
      "empty_tag" => ""
    }

    conn = get(conn, "/users/register?" <> URI.encode_query(campaign))
    document = conn |> html_response(200) |> Floki.parse_document!()
    fields = Floki.find(document, "#user-registration-form input[type=hidden]")

    for {key, value} <- campaign do
      assert Enum.any?(fields, fn field ->
               Floki.attribute(field, "name") == ["user[signup_campaign][#{key}]"] and
                 Floki.attribute(field, "value") == [value]
             end)
    end

    conn =
      post(recycle(conn), ~p"/users/register", %{
        "user" => %{"email" => "invalid", "password" => "short", "signup_campaign" => campaign}
      })

    document = conn |> html_response(200) |> Floki.parse_document!()

    assert Floki.attribute(document, "input[name='user[signup_campaign][utm_campaign]']", "value") ==
             ["autumn & winter"]

    email = unique_user_email()

    conn =
      post(recycle(conn), ~p"/users/register", %{
        "user" =>
          valid_user_attributes(
            email: email,
            signup_campaign: Map.put(campaign, "nested", %{"invalid" => "value"})
          )
      })

    assert redirected_to(conn) == "/users/confirm"
    user = Shroud.Accounts.get_user_by_email(email)
    assert_receive {:signup_event, %{"type" => "track", "payload" => payload}}, 2_000
    assert payload["name"] == "signup"
    assert payload["profileId"] == Shroud.Analytics.profile_id(user.id)
    path = URI.parse(payload["properties"]["__path"])
    assert path.path == "/users/register"
    assert URI.decode_query(path.query) == campaign
    assert_receive {:signup_event, %{"type" => "identify", "payload" => identity}}, 2_000
    assert identity == %{"profileId" => Shroud.Analytics.profile_id(user.id)}
  end

  test "CAPTCHA retry preserves query tags and lifetime selection", %{conn: conn} do
    enable_cap()

    conn =
      post(conn, ~p"/users/register", %{
        "user" => %{
          "status" => "lifetime",
          "signup_campaign" => %{"utm_source" => "newsletter", "gclid" => "private"}
        }
      })

    url = URI.parse(redirected_to(conn))
    assert url.path == "/users/register"

    assert URI.decode_query(url.query) == %{
             "utm_source" => "newsletter",
             "gclid" => "private",
             "lifetime" => "true"
           }
  after
    disable_cap()
  end

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      response = html_response(conn, 200)
      assert response =~ "Sign up"
      login_links = response |> Floki.parse_document!() |> Floki.find("a[href='/users/log_in']")
      assert Enum.any?(login_links, &(Floki.text(&1) |> String.trim() == "Log in"))
    end

    test "redirects if already logged in", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/users/register")
      assert redirected_to(conn) == "/"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account and logs the user in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/confirm"
      refute Flash.get(conn.assigns.flash, :info)

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/users/confirm")
      response = html_response(conn, 200)
      assert response =~ email
      document = LazyHTML.from_document(response)

      assert document |> LazyHTML.query("p.prose") |> LazyHTML.text() =~
               "We sent you an email with a confirmation link."

      assert document |> LazyHTML.query("#flash-info") |> Enum.empty?()

      assert document |> LazyHTML.query("#user-menu-item-0") |> LazyHTML.text() |> String.trim() ==
               "Settings"

      assert document |> LazyHTML.query("#user-menu-item-1") |> LazyHTML.text() |> String.trim() ==
               "Log out"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/users/register", %{
          "user" => %{"email" => "with spaces", "password" => "too short"}
        })

      response = html_response(conn, 200)
      assert response =~ "Sign up"
      assert response =~ "is invalid"
      assert response =~ "should be at least 12 character"
    end

    test "creates a lifetime user", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email, status: :lifetime)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/confirm"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/users/confirm")
      assert conn.assigns.current_user.status == :lifetime
    end
  end

  describe "POST /users/register with Cap enabled" do
    test "rejects a forged POST with no cap-token", %{conn: conn} do
      enable_cap()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: unique_user_email())
        })

      assert redirected_to(conn) == "/users/register"
      assert Flash.get(conn.assigns.flash, :error) =~ "verification"
    after
      disable_cap()
    end

    test "creates account when cap-token verifies", %{conn: conn} do
      enable_cap()

      Req.Test.stub(Shroud.Captcha, fn conn ->
        Req.Test.json(conn, %{"success" => true})
      end)

      email = unique_user_email()

      conn =
        post(conn, ~p"/users/register", %{
          "user" => valid_user_attributes(email: email),
          "cap-token" => "valid-token"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/users/confirm"
    after
      disable_cap()
    end
  end
end
