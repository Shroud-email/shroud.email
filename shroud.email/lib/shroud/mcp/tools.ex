defmodule Shroud.Mcp.Tools do
  @moduledoc "The bounded alias-management surface exposed to MCP clients."
  require Logger
  alias ExMCP.Content.SchemaPolicy
  alias Shroud.{Aliases, Domain}

  def list do
    address = string("Exact alias address", 320)
    title = string("Alias label", 255)
    notes = string("Alias notes", 2000, 0)

    page = %{
      type: "integer",
      minimum: 1,
      description: "Page number, starting at 1; ten results per page"
    }

    alias_output =
      object(
        %{
          address: %{type: "string"},
          title: %{type: ["string", "null"]},
          notes: %{type: ["string", "null"]},
          enabled: %{type: "boolean"}
        },
        [:address, :title, :notes, :enabled]
      )

    [
      tool(
        "list_aliases",
        "List aliases",
        "Search aliases by their address or label or notes.",
        "aliases:read",
        object(
          %{
            search: string("Search address, label or notes; omit to list all aliases", 255, 0),
            enabled: %{type: "boolean", description: "Filter enabled or disabled aliases"},
            page: page
          },
          []
        ),
        object(
          %{
            aliases: %{type: "array", items: alias_output},
            has_more: %{type: "boolean"}
          },
          [:aliases, :has_more]
        ),
        true,
        false
      ),
      tool(
        "get_alias",
        "Get an alias",
        "Get an alias's address, label, notes and enabled status.",
        "aliases:read",
        object(%{address: address}, [:address]),
        alias_output,
        true,
        false
      ),
      tool(
        "create_alias",
        "Create a labelled alias",
        "Create an alias with a label and optional notes. For a custom domain, supply both domain and local_part.",
        "aliases:create",
        object(
          %{
            title: title,
            notes: notes,
            domain: string("Existing verified custom domain", 253),
            local_part: string("Local part without @, spaces or underscores", 64)
          },
          [:title]
        ),
        alias_output,
        false,
        false
      ),
      tool(
        "edit_alias",
        "Edit an alias",
        "Update an alias's label, notes or enabled status. An empty string clears a label or notes. Disabling stops forwarding immediately, including password-reset emails.",
        "aliases:edit",
        object(
          %{
            address: address,
            title: string("Replacement label; empty clears it", 255, 0),
            notes: notes,
            enabled: %{type: "boolean", description: "Enable or disable forwarding"}
          },
          [:address]
        ),
        alias_output,
        false,
        true
      ),
      tool(
        "list_verified_domains",
        "List verified custom domains",
        "List verified custom domains available for alias creation.",
        "domains:read",
        object(%{page: page}, []),
        object(
          %{domains: %{type: "array", items: %{type: "string"}}, has_more: %{type: "boolean"}},
          [:domains, :has_more]
        ),
        true,
        false
      )
    ]
  end

  def scope(name) do
    case Enum.find(list(), &(&1.name == name)) do
      nil -> nil
      tool -> hd(tool.securitySchemes).scopes |> hd()
    end
  end

  def call(connection, name, arguments) do
    with tool when not is_nil(tool) <- Enum.find(list(), &(&1.name == name)),
         :ok <- SchemaPolicy.validate(arguments, tool.inputSchema) do
      execute(connection, name, arguments)
    else
      nil ->
        {:error, "Unknown tool"}

      {:error, errors} when is_list(errors) ->
        {:error, "Invalid tool arguments"}

      {:error, reason} ->
        category =
          case reason do
            {category, _} when is_atom(category) -> category
            {category, _, _} when is_atom(category) -> category
            _ -> :schema_policy_failure
          end

        Logger.warning("MCP schema validation unavailable (#{category})")
        {:error, "Tool unavailable; please try again."}
    end
  end

  defp execute(connection, "list_aliases", args) do
    page =
      Aliases.list_aliases_page(connection.user,
        search: args["search"],
        enabled: args["enabled"],
        page: Map.get(args, "page", 1),
        page_size: 10
      )

    {:ok,
     %{
       aliases: Enum.map(page.entries, &alias_data/1),
       has_more: page.has_more
     }}
  end

  defp execute(connection, "create_alias", args) do
    attrs =
      for key <- ~w(title notes domain local_part), Map.has_key?(args, key), into: %{} do
        {String.to_existing_atom(key), args[key]}
      end

    connection.user |> Aliases.create_email_alias(attrs) |> alias_result()
  end

  defp execute(connection, "list_verified_domains", args) do
    domains =
      connection.user
      |> Domain.list_verified_custom_domains()
      |> Enum.drop(offset(args))
      |> Enum.take(11)

    {:ok,
     %{domains: Enum.take(domains, 10) |> Enum.map(& &1.domain), has_more: length(domains) > 10}}
  end

  defp execute(connection, name, args) do
    email_alias = Aliases.get_email_alias_by_address(connection.user, args["address"])

    case {email_alias, name} do
      {nil, _} ->
        {:error, "Alias not found"}

      {email_alias, "get_alias"} ->
        {:ok, alias_data(email_alias)}

      {email_alias, "edit_alias"} ->
        attrs = Map.take(args, ["title", "notes", "enabled"])

        if map_size(attrs) == 0,
          do: {:error, "Supply a label, notes or enabled status to edit"},
          else: alias_result(Aliases.update_email_alias(email_alias, attrs))
    end
  end

  defp alias_result({:ok, email_alias}), do: {:ok, alias_data(email_alias)}
  defp alias_result({:error, :inactive_user}), do: {:error, "Account is inactive"}

  defp alias_result({:error, :free_limit_reached}),
    do:
      {:error,
       "Your account's alias limit has been reached. Upgrade for more aliases: #{Shroud.Mcp.issuer()}/settings/billing"}

  defp alias_result({:error, :invalid_domain}),
    do: {:error, "Supply both a valid local part and an existing verified custom domain"}

  defp alias_result({:error, %Ecto.Changeset{}}),
    do: {:error, "Alias could not be saved; check the address and metadata"}

  defp alias_data(email_alias), do: Map.take(email_alias, [:address, :title, :notes, :enabled])

  defp offset(args), do: (Map.get(args, "page", 1) - 1) * 10

  defp string(description, max, min \\ 1) do
    schema = %{type: "string", description: description, minLength: min, maxLength: max}
    if min > 0, do: Map.put(schema, :pattern, "\\S"), else: schema
  end

  defp object(properties, required),
    do: %{
      type: "object",
      properties: properties,
      required: Enum.map(required, &Atom.to_string/1),
      additionalProperties: false
    }

  defp tool(name, title, description, scope, input, output, read_only, destructive) do
    security_schemes = [%{type: "oauth2", scopes: Shroud.Mcp.required_scopes(scope)}]

    %{
      name: name,
      title: title,
      description: description,
      inputSchema: input,
      outputSchema: output,
      annotations: %{readOnlyHint: read_only, destructiveHint: destructive, openWorldHint: false},
      securitySchemes: security_schemes,
      _meta: %{"securitySchemes" => security_schemes}
    }
  end
end
