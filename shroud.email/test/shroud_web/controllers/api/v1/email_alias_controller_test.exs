defmodule ShroudWeb.Api.V1.EmailAliasControllerTest do
  use ShroudWeb.ConnCase, async: true
  import OpenApiSpex.TestAssertions, only: [assert_raw_schema: 2]
  alias Shroud.Accounts
  import Shroud.{AccountsFixtures, AliasesFixtures, DomainFixtures}
  alias Shroud.Repo
  alias ShroudWeb.Api.V1.Schemas

  describe "index/2" do
    setup do
      conn = build_conn()
      user = user_fixture()

      user =
        user
        |> Accounts.User.confirm_changeset()
        |> Repo.update!(returning: true)

      email_alias_1 = alias_fixture(%{user_id: user.id})
      email_alias_2 = alias_fixture(%{user_id: user.id})
      # First email alias was created an hour ago (i.e. should come last in ordering)
      one_hour_ago =
        NaiveDateTime.add(NaiveDateTime.utc_now(), -3600, :second)
        |> NaiveDateTime.truncate(:second)

      email_alias_1
      |> Accounts.User.inserted_at_changeset(%{inserted_at: one_hour_ago})
      |> Repo.update!()

      %{conn: conn, user: user, email_alias_1: email_alias_1, email_alias_2: email_alias_2}
    end

    test "renders a list of email aliases", %{
      conn: conn,
      user: user,
      email_alias_1: email_alias_1,
      email_alias_2: email_alias_2
    } do
      conn = authorized_get(conn, user, ~p"/api/v1/aliases")

      assert_raw_schema(json_response(conn, 200), Schemas.aliases_page())

      assert json_response(conn, 200) == %{
               "email_aliases" => [
                 %{
                   "address" => email_alias_2.address,
                   "enabled" => email_alias_2.enabled,
                   "title" => email_alias_2.title,
                   "notes" => email_alias_2.notes,
                   "forwarded" => email_alias_2.forwarded,
                   "blocked" => email_alias_2.blocked,
                   "blocked_addresses" => []
                 },
                 %{
                   "address" => email_alias_1.address,
                   "enabled" => email_alias_1.enabled,
                   "title" => email_alias_1.title,
                   "notes" => email_alias_1.notes,
                   "forwarded" => email_alias_1.forwarded,
                   "blocked" => email_alias_1.blocked,
                   "blocked_addresses" => []
                 }
               ],
               "page_number" => 1,
               "page_size" => 20,
               "total_entries" => 2,
               "total_pages" => 1
             }
    end

    test "only renders aliases from the current user", %{conn: conn, user: user} do
      other_user = user_fixture()
      _other_alias = alias_fixture(%{user_id: other_user.id})

      conn = authorized_get(conn, user, ~p"/api/v1/aliases")

      assert length(json_response(conn, 200)["email_aliases"]) == 2
    end

    test "handles page_size parameter", %{conn: conn, user: user, email_alias_2: email_alias_2} do
      conn =
        authorized_get(conn, user, ~p"/api/v1/aliases", %{"page_size" => 1})

      assert length(json_response(conn, 200)["email_aliases"]) == 1
      assert hd(json_response(conn, 200)["email_aliases"])["address"] == email_alias_2.address
    end

    test "handles page parameter", %{conn: conn, user: user, email_alias_1: email_alias_1} do
      conn =
        authorized_get(conn, user, ~p"/api/v1/aliases", %{
          "page_size" => 1,
          "page" => 2
        })

      assert length(json_response(conn, 200)["email_aliases"]) == 1
      assert hd(json_response(conn, 200)["email_aliases"])["address"] == email_alias_1.address
    end

    test "searches address, title, and notes case-insensitively within the current account", %{
      conn: conn,
      user: user
    } do
      matches = [
        alias_fixture(%{user_id: user.id, address: "acme@email.shroud.test"}),
        alias_fixture(%{user_id: user.id, title: "Acme shopping"}),
        alias_fixture(%{user_id: user.id, notes: "Used for ACME receipts"})
      ]

      alias_fixture(%{user_id: user_fixture().id, title: "Acme"})
      deleted = alias_fixture(%{user_id: user.id, title: "Acme"})
      Shroud.Aliases.delete_email_alias(deleted.id)

      conn = authorized_get(conn, user, ~p"/api/v1/aliases", %{"search" => "aCmE"})
      response = json_response(conn, 200)

      assert response["total_entries"] == 3

      assert Enum.sort(Enum.map(response["email_aliases"], & &1["address"])) ==
               Enum.sort(Enum.map(matches, & &1.address))
    end

    test "combines search and enabled filters before pagination", %{conn: conn, user: user} do
      disabled = alias_fixture(%{user_id: user.id, title: "Acme", enabled: false})
      alias_fixture(%{user_id: user.id, title: "Acme", enabled: true})
      alias_fixture(%{user_id: user.id, title: "Other", enabled: false})

      conn =
        authorized_get(conn, user, ~p"/api/v1/aliases", %{
          "search" => "Acme",
          "enabled" => "false",
          "page_size" => 1
        })

      response = json_response(conn, 200)
      assert response["total_entries"] == 1
      assert response["total_pages"] == 1
      assert Enum.map(response["email_aliases"], & &1["address"]) == [disabled.address]
    end

    test "filters enabled aliases and counts all search matches across pages", %{
      conn: conn,
      user: user
    } do
      alias_fixture(%{user_id: user.id, title: "Acme", enabled: true})
      alias_fixture(%{user_id: user.id, title: "Acme", enabled: true})
      alias_fixture(%{user_id: user.id, title: "Acme", enabled: false})

      conn =
        authorized_get(conn, user, ~p"/api/v1/aliases", %{
          "search" => "Acme",
          "enabled" => "true",
          "page_size" => 1,
          "page" => 2
        })

      response = json_response(conn, 200)
      assert response["total_entries"] == 2
      assert response["total_pages"] == 2
      assert [%{"enabled" => true, "title" => "Acme"}] = response["email_aliases"]
    end

    test "handles blank search, no matches, and invalid filters", %{conn: conn, user: user} do
      for search <- ["", "   "] do
        response =
          conn
          |> authorized_get(user, ~p"/api/v1/aliases", %{"search" => search})
          |> json_response(200)

        assert response["total_entries"] == 2
      end

      response =
        conn
        |> authorized_get(user, ~p"/api/v1/aliases", %{"search" => "no-such-alias"})
        |> json_response(200)

      assert response["email_aliases"] == []
      assert response["total_entries"] == 0

      for params <- [%{"enabled" => "sometimes"}, %{"search" => ["Acme"]}] do
        response = conn |> authorized_get(user, ~p"/api/v1/aliases", params) |> json_response(422)
        assert response == %{"error" => "Invalid search or enabled filter"}
      end
    end
  end

  describe "create/2" do
    setup do
      conn = build_conn()
      user = user_fixture()

      user =
        user
        |> Accounts.User.confirm_changeset()
        |> Repo.update!(returning: true)

      %{conn: conn, user: user}
    end

    test "creates an email alias", %{conn: conn, user: user} do
      conn = authorized_post(conn, user, ~p"/api/v1/aliases")

      response = json_response(conn, 200)

      assert_raw_schema(response, Schemas.email_alias())

      assert %{response | "address" => nil} == %{
               "address" => nil,
               "blocked" => 0,
               "forwarded" => 0,
               "title" => nil,
               "notes" => nil,
               "blocked_addresses" => [],
               "enabled" => true
             }

      assert String.ends_with?(response["address"], "@email.shroud.test")
    end

    test "creates labelled random and custom-domain aliases without accepting internal fields", %{
      conn: conn,
      user: user
    } do
      custom_domain_fixture(%{user_id: user.id, domain: "custom.test"})
      other_user = user_fixture()

      for address_params <- [%{}, %{"local_part" => "labelled", "domain" => "custom.test"}] do
        params =
          Map.merge(address_params, %{
            "title" => "Acme",
            "notes" => "Shopping receipts",
            "user_id" => other_user.id,
            "address" => "injected@email.shroud.test",
            "domain_id" => 123,
            "forwarded" => 999,
            "enabled" => false
          })

        response =
          conn |> authorized_post(user, ~p"/api/v1/aliases", params) |> json_response(200)

        assert response["title"] == "Acme"
        assert response["notes"] == "Shopping receipts"
        assert response["enabled"] == true
        assert response["forwarded"] == 0
        refute response["address"] == "injected@email.shroud.test"

        assert Repo.get_by!(Shroud.Aliases.EmailAlias, address: response["address"]).user_id ==
                 user.id
      end
    end

    test "rejects invalid metadata on random and custom-domain aliases", %{conn: conn, user: user} do
      custom_domain_fixture(%{user_id: user.id, domain: "custom.test"})

      for address_params <- [%{}, %{"local_part" => "invalid", "domain" => "custom.test"}] do
        params = Map.merge(address_params, %{"title" => ["invalid"]})

        response =
          conn |> authorized_post(user, ~p"/api/v1/aliases", params) |> json_response(422)

        assert response == %{"error" => "is invalid"}
      end

      assert Repo.aggregate(Shroud.Aliases.EmailAlias, :count) == 0
    end

    test "rejects incomplete or wrongly typed custom address parameters without creating aliases",
         %{
           conn: conn,
           user: user
         } do
      custom_domain_fixture(%{user_id: user.id, domain: "custom.test"})

      for params <- [
            %{"local_part" => "acme"},
            %{"domain" => "custom.test"},
            %{"local_part" => nil, "domain" => "custom.test"},
            %{"local_part" => "acme", "domain" => nil},
            %{"local_part" => ["acme"], "domain" => "custom.test"},
            %{"local_part" => 123, "domain" => "custom.test"},
            %{"local_part" => "acme", "domain" => %{"name" => "custom.test"}}
          ] do
        response =
          conn |> authorized_post(user, ~p"/api/v1/aliases", params) |> json_response(422)

        assert response == %{"error" => "local_part and domain must both be strings"}
      end

      assert Repo.aggregate(Shroud.Aliases.EmailAlias, :count) == 0
    end

    test "cannot create aliases on another user's custom domain", %{conn: conn, user: user} do
      custom_domain_fixture(%{user_id: user_fixture().id, domain: "other.test"})

      conn =
        authorized_post(conn, user, ~p"/api/v1/aliases", %{
          "local_part" => "acme",
          "domain" => "other.test",
          "title" => "Acme"
        })

      assert json_response(conn, 422) == %{"error" => "Domain not found"}
    end

    test "creates an email alias on a custom domain", %{conn: conn, user: user} do
      custom_domain_fixture(%{user_id: user.id, domain: "custom.test"})

      conn =
        authorized_post(conn, user, ~p"/api/v1/aliases", %{
          local_part: "email",
          domain: "custom.test"
        })

      assert json_response(conn, 200) == %{
               "address" => "email@custom.test",
               "blocked" => 0,
               "forwarded" => 0,
               "title" => nil,
               "notes" => nil,
               "blocked_addresses" => [],
               "enabled" => true
             }
    end

    test "prevents creating an email alias on an invalid domain", %{conn: conn, user: user} do
      conn =
        authorized_post(conn, user, ~p"/api/v1/aliases", %{
          local_part: "email",
          domain: "custom.test"
        })

      assert json_response(conn, 422) == %{
               "error" => "Domain not found"
             }
    end

    test "prevents creating an invalid local part", %{conn: conn, user: user} do
      custom_domain_fixture(%{user_id: user.id, domain: "custom.test"})

      conn =
        authorized_post(conn, user, ~p"/api/v1/aliases", %{
          local_part: "invalid local part",
          domain: "custom.test"
        })

      assert json_response(conn, 422) == %{
               "error" => "must have an @ sign and no spaces or underscores"
             }
    end

    test "returns 403 when free user exceeds alias limit", %{conn: conn} do
      free_user = user_fixture(%{status: :free})

      free_user =
        free_user
        |> Accounts.User.confirm_changeset()
        |> Repo.update!(returning: true)

      # Create 5 aliases to hit the limit
      Enum.each(1..5, fn idx ->
        alias_fixture(%{user_id: free_user.id, address: "alias#{idx}@email.shroud.test"})
      end)

      conn = authorized_post(conn, free_user, ~p"/api/v1/aliases")

      assert json_response(conn, 403) == %{
               "error" => "Free plan alias limit reached. Upgrade to create more aliases."
             }
    end
  end

  describe "lookup and update" do
    setup do
      user = user_fixture()
      user = user |> Accounts.User.confirm_changeset() |> Repo.update!()
      email_alias = alias_fixture(%{user_id: user.id, title: "Acme", notes: "Receipts"})

      %{conn: build_conn(), user: user, email_alias: email_alias}
    end

    test "fetches an exact alias address", %{conn: conn, user: user, email_alias: email_alias} do
      conn = authorized_get(conn, user, ~p"/api/v1/aliases/#{email_alias.address}")

      assert_raw_schema(json_response(conn, 200), Schemas.email_alias())

      assert %{
               "address" => address,
               "title" => "Acme",
               "notes" => "Receipts",
               "enabled" => true
             } = json_response(conn, 200)

      assert address == email_alias.address
    end

    test "updates metadata and disables then re-enables an alias", %{
      conn: conn,
      user: user,
      email_alias: email_alias
    } do
      path = ~p"/api/v1/aliases/#{email_alias.address}"

      response =
        conn
        |> authorized_patch(user, path, %{"title" => "Acme shop", "enabled" => false})
        |> json_response(200)

      assert response["title"] == "Acme shop"
      assert response["notes"] == "Receipts"
      assert response["enabled"] == false
      assert Repo.reload!(email_alias).enabled == false

      response =
        conn
        |> authorized_patch(user, path, %{"notes" => "Updated notes", "enabled" => true})
        |> json_response(200)

      assert response["title"] == "Acme shop"
      assert response["notes"] == "Updated notes"
      assert response["enabled"] == true
      assert Repo.reload!(email_alias).enabled == true
    end

    test "clears optional metadata with null without changing enabled state", %{
      conn: conn,
      user: user,
      email_alias: email_alias
    } do
      response =
        conn
        |> authorized_patch(user, ~p"/api/v1/aliases/#{email_alias.address}", %{
          "title" => nil,
          "notes" => nil
        })
        |> json_response(200)

      assert_raw_schema(response, Schemas.email_alias())

      assert response["title"] == nil
      assert response["notes"] == nil
      assert response["enabled"] == true
    end

    test "ignores attempts to change address, ownership, counters, and other internal fields", %{
      conn: conn,
      user: user,
      email_alias: email_alias
    } do
      params = %{
        "title" => "Updated",
        "address" => "changed@email.shroud.test",
        "user_id" => user_fixture().id,
        "domain_id" => 123,
        "forwarded" => 999,
        "blocked_addresses" => ["someone@example.com"],
        "deleted_at" => "2026-01-01T00:00:00"
      }

      conn = authorized_patch(conn, user, ~p"/api/v1/aliases/#{email_alias.address}", params)
      assert json_response(conn, 200)["address"] == email_alias.address
      updated = Repo.reload!(email_alias)
      assert updated.title == "Updated"
      assert updated.address == email_alias.address
      assert updated.user_id == user.id
      assert updated.domain_id == email_alias.domain_id
      assert updated.forwarded == 0
      assert updated.blocked_addresses == []
      assert updated.deleted_at == nil
    end

    test "rejects invalid updates atomically", %{conn: conn, user: user, email_alias: email_alias} do
      for params <- [
            %{"enabled" => "sometimes", "title" => "Should not persist"},
            %{"enabled" => nil},
            %{"title" => ["invalid"]},
            %{"notes" => %{"invalid" => true}}
          ] do
        conn = authorized_patch(conn, user, ~p"/api/v1/aliases/#{email_alias.address}", params)
        assert %{"error" => error} = json_response(conn, 422)
        assert is_binary(error)
        assert Repo.reload!(email_alias).title == "Acme"
        assert Repo.reload!(email_alias).enabled == true
      end
    end

    test "does not expose or edit missing, deleted, or other users' aliases", %{
      conn: conn,
      user: user,
      email_alias: email_alias
    } do
      other_alias = alias_fixture(%{user_id: user_fixture().id, title: "Other user"})
      Shroud.Aliases.delete_email_alias(email_alias.id)

      for address <- ["missing@email.shroud.test", email_alias.address, other_alias.address] do
        path = ~p"/api/v1/aliases/#{address}"

        assert conn |> authorized_get(user, path) |> json_response(404) ==
                 %{"error" => "Alias not found"}

        assert conn |> authorized_patch(user, path, %{"enabled" => false}) |> json_response(404) ==
                 %{"error" => "Alias not found"}
      end

      assert Repo.reload!(other_alias).enabled == true
      assert Repo.reload!(email_alias).enabled == true
    end

    test "requires authentication and a confirmed account", %{
      conn: conn,
      email_alias: email_alias
    } do
      path = ~p"/api/v1/aliases/#{email_alias.address}"
      assert conn |> get(path) |> json_response(403) == %{"error" => "Invalid token"}

      assert conn |> patch(path, %{"enabled" => false}) |> json_response(403) ==
               %{"error" => "Invalid token"}

      unconfirmed = user_fixture()

      assert conn |> authorized_get(unconfirmed, path) |> json_response(403) ==
               %{"error" => "Please confirm your account"}

      assert conn
             |> authorized_patch(unconfirmed, path, %{"enabled" => false})
             |> json_response(403) ==
               %{"error" => "Please confirm your account"}
    end
  end

  describe "delete/2" do
    setup do
      conn = build_conn()
      user = user_fixture()

      user =
        user
        |> Accounts.User.confirm_changeset()
        |> Repo.update!(returning: true)

      email_alias = alias_fixture(%{user_id: user.id})

      %{conn: conn, user: user, address: email_alias.address}
    end

    test "deletes an email alias", %{conn: conn, user: user, address: address} do
      conn = authorized_delete(conn, user, ~p"/api/v1/aliases/#{address}")
      assert response(conn, 204)
    end

    test "returns 422 for missing and deleted aliases", %{
      conn: conn,
      user: user,
      address: address
    } do
      conn |> authorized_delete(user, ~p"/api/v1/aliases/#{address}") |> response(204)

      for address <- [address, "missing@email.shroud.test"] do
        assert conn
               |> authorized_delete(user, ~p"/api/v1/aliases/#{address}")
               |> json_response(422) ==
                 %{"error" => "Alias not found"}
      end
    end

    test "prevents deleting an email alias if user does not own it", %{conn: conn, user: user} do
      other_user = user_fixture()
      other_alias = alias_fixture(%{user_id: other_user.id})

      conn =
        authorized_delete(conn, user, ~p"/api/v1/aliases/#{other_alias.address}")

      assert json_response(conn, 422) == %{
               "error" => "Alias not found"
             }
    end
  end

  defp authorized_get(conn, user, path, params \\ nil) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> put_req_header("authorization", "Bearer #{Base.encode64(token)}")
    |> get(path, params)
  end

  defp authorized_post(conn, user, path, params \\ nil) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> put_req_header("authorization", "Bearer #{Base.encode64(token)}")
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(params || %{}))
  end

  defp authorized_patch(conn, user, path, params) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> put_req_header("authorization", "Bearer #{Base.encode64(token)}")
    |> put_req_header("content-type", "application/json")
    |> patch(path, Jason.encode!(params))
  end

  defp authorized_delete(conn, user, path, params \\ nil) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> put_req_header("authorization", "Bearer #{Base.encode64(token)}")
    |> delete(path, params)
  end
end
