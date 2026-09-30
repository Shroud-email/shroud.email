defmodule ShroudWeb.Api.V1.Schemas do
  @moduledoc "Documentation-only schemas for the v1 JSON API."
  alias OpenApiSpex.Schema

  def email_alias do
    %Schema{
      title: "EmailAlias",
      type: :object,
      required: [:address, :enabled, :title, :notes, :forwarded, :blocked, :blocked_addresses],
      properties: %{
        address: %Schema{type: :string, format: :email},
        enabled: %Schema{type: :boolean},
        title: metadata(),
        notes: metadata(),
        forwarded: %Schema{type: :integer, minimum: 0},
        blocked: %Schema{type: :integer, minimum: 0},
        blocked_addresses: %Schema{type: :array, items: %Schema{type: :string}}
      },
      example: %{
        address: "deadbeef@fog.shroud.email",
        enabled: true,
        title: "Newsletters",
        notes: "Used for webshop newsletters etc.",
        forwarded: 26,
        blocked: 33,
        blocked_addresses: ["spammer@example.com"]
      }
    }
  end

  def create_alias do
    %Schema{
      title: "CreateAlias",
      type: :object,
      description:
        "Omit both local_part and domain for a random alias; otherwise supply both strings.",
      properties: %{
        local_part: %Schema{type: :string},
        domain: %Schema{type: :string},
        title: metadata(),
        notes: metadata()
      },
      allOf: [
        %Schema{
          not: %Schema{
            oneOf: [
              %Schema{type: :object, required: [:local_part]},
              %Schema{type: :object, required: [:domain]}
            ]
          }
        }
      ],
      example: %{
        local_part: "myemail",
        domain: "example.com",
        title: "Acme",
        notes: "Used for shopping receipts"
      }
    }
  end

  def update_alias do
    %Schema{
      title: "UpdateAlias",
      type: :object,
      properties: %{title: metadata(), notes: metadata(), enabled: %Schema{type: :boolean}},
      example: %{title: "Acme shopping", notes: "Receipts and order updates", enabled: false}
    }
  end

  def token_request do
    %Schema{
      title: "CreateToken",
      type: :object,
      required: [:email, :password],
      properties: %{
        email: %Schema{type: :string, format: :email},
        password: %Schema{type: :string, format: :password},
        totp: %Schema{
          type: :integer,
          description: "Required when two-factor authentication is enabled."
        }
      },
      example: %{email: "user@example.com", password: "correcthorsebatterystaple", totp: 123_456}
    }
  end

  def token do
    %Schema{
      title: "Token",
      type: :object,
      required: [:token],
      properties: %{token: %Schema{type: :string, description: "Base64-encoded session token."}},
      example: %{token: "c2hyb3VkLmVtYWlsIHRva2VuIDotKQ=="}
    }
  end

  def error do
    %Schema{
      title: "Error",
      type: :object,
      required: [:error],
      properties: %{error: %Schema{type: :string}},
      example: %{error: "Invalid token"}
    }
  end

  def aliases_page do
    alias_schema = email_alias()
    page(:email_aliases, alias_schema, alias_schema.example)
  end

  def domains_page do
    domain = %Schema{
      type: :object,
      required: [:domain],
      properties: %{domain: %Schema{type: :string}}
    }

    page(:domains, domain, %{domain: "example.com"})
  end

  def pagination_parameters do
    [
      page: [in: :query, type: :integer, description: "Page number (default 1).", example: 1],
      page_size: [
        in: :query,
        type: :integer,
        description: "Entries per page (default 20).",
        example: 20
      ]
    ]
  end

  def address_parameter do
    [
      address: [
        in: :path,
        type: :string,
        required: true,
        description: "Exact alias address. URL-encode it, e.g. deadbeef%40fog.shroud.email.",
        example: "deadbeef@fog.shroud.email"
      ]
    ]
  end

  defp metadata, do: %Schema{type: :string, nullable: true}

  defp page(key, item, example) do
    %Schema{
      type: :object,
      required: [key, :page_number, :page_size, :total_entries, :total_pages],
      properties: %{
        key => %Schema{type: :array, items: item},
        :page_number => %Schema{type: :integer},
        :page_size => %Schema{type: :integer},
        :total_entries => %Schema{type: :integer},
        :total_pages => %Schema{type: :integer}
      },
      example: %{
        key => [example],
        :page_number => 1,
        :page_size => 20,
        :total_entries => 1,
        :total_pages => 1
      }
    }
  end
end
