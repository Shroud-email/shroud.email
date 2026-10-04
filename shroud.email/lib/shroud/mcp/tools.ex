defmodule Shroud.Mcp.Tools do
  @moduledoc "The bounded alias-management surface exposed to MCP clients."
  require Logger
  import Ecto.Query
  alias ExMCP.Content.SchemaPolicy
  alias Shroud.{Aliases, Domain, Repo}

  def list do
    address = string("Exact alias address", 320)
    title = string("Alias title", 255)
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
          enabled: %{type: "boolean"},
          created_at: %{type: "string", format: "date-time", description: "Creation time in UTC"}
        },
        [:address, :title, :notes, :enabled, :created_at]
      )

    [
      tool(
        "list_aliases",
        "List aliases",
        "List or search aliases, ordered by creation time, newest first. Search uses case-insensitive literal substring matching: every whitespace-separated word must match address, title, or notes, possibly in different fields. Empty search lists all aliases.",
        object(
          %{
            search: string("Search address, title or notes; omit to list all aliases", 255, 0),
            enabled: %{type: "boolean", description: "Filter enabled or disabled aliases"},
            page: %{
              page
              | description: "Page number, starting at 1; results per page are set by limit"
            },
            limit: %{
              type: "integer",
              minimum: 1,
              maximum: 100,
              default: 10,
              description: "Results per page"
            }
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
        "Get an alias's address, title, notes, enabled status and creation timestamp.",
        object(%{address: address}, [:address]),
        alias_output,
        true,
        false
      ),
      tool(
        "create_alias",
        "Create an alias",
        "Create a forwarding alias with a title and optional notes. Omit domain to use a Shroud.email-managed domain. Supply a verified custom domain to use it. Omit local_part to generate a random address, or submit your own.",
        object(
          %{
            title: title,
            notes: notes,
            domain: string("Existing verified custom domain", 253),
            local_part:
              Map.put(
                string(
                  "Local part without @, spaces or underscores; requires a custom domain",
                  64
                ),
                :pattern,
                "^[^@\\s_]+$"
              )
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
        "Update an alias's title, notes or forwarding status. Omitted fields remain unchanged. An empty string clears the title or notes. Disabling immediately stops forwarding.",
        object(
          %{
            address: address,
            title: string("Replacement title; empty clears it", 255, 0),
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

  def scope(name) when name in ["list_aliases", "get_alias"], do: "aliases:read"
  def scope("create_alias"), do: "aliases:create"
  def scope("edit_alias"), do: "aliases:edit"
  def scope("list_verified_domains"), do: "domains:read"
  def scope(_name), do: nil

  def call(connection, name, arguments) do
    with tool when not is_nil(tool) <- Enum.find(list(), &(&1.name == name)),
         :ok <- SchemaPolicy.validate(arguments, tool.inputSchema) do
      arguments =
        Map.new(arguments, fn
          {key, value} when key in ["page", "limit"] and is_float(value) -> {key, trunc(value)}
          entry -> entry
        end)

      execute(connection, name, arguments)
    else
      nil ->
        error("UNKNOWN_TOOL", "Unknown tool")

      {:error, errors} when is_list(errors) ->
        error("INVALID_ARGUMENT", "Invalid tool arguments")

      {:error, reason} ->
        category =
          case reason do
            {category, _} when is_atom(category) -> category
            {category, _, _} when is_atom(category) -> category
            _ -> :schema_policy_failure
          end

        Logger.warning("MCP schema validation unavailable (#{category})")
        error("SERVICE_UNAVAILABLE", "Tool unavailable; please try again.")
    end
  end

  defp execute(connection, "list_aliases", args) do
    query = Aliases.aliases_query(connection.user, args["search"])

    query =
      if is_boolean(args["enabled"]),
        do: where(query, [a], a.enabled == ^args["enabled"]),
        else: query

    page =
      Repo.paginate(query,
        page: Map.get(args, "page", 1),
        page_size: Map.get(args, "limit", 10),
        options: [allow_overflow_page_number: true]
      )

    {:ok,
     %{
       aliases: Enum.map(page.entries, &alias_data/1),
       has_more: page.page_number < page.total_pages
     }}
  end

  defp execute(connection, "create_alias", args) do
    attrs =
      for key <- ~w(title notes), Map.has_key?(args, key), into: %{} do
        {String.to_existing_atom(key), args[key]}
      end

    result =
      case {args["domain"], args["local_part"]} do
        {nil, nil} ->
          Aliases.create_random_email_alias(connection.user, attrs)

        {domain, local} when is_binary(domain) ->
          owned =
            Domain.list_custom_domains(connection.user)
            |> Enum.find(&(String.downcase(&1.domain) == String.downcase(domain)))

          cond do
            is_nil(owned) ->
              error("DOMAIN_NOT_FOUND", "Supply an existing custom domain owned by your account")

            not Domain.fully_verified?(owned) ->
              error("DOMAIN_NOT_VERIFIED", "Verify the custom domain before creating an alias")

            true ->
              stored_domain = owned.domain
              local = local || Aliases.generate_alias_name(String.downcase(stored_domain))

              Aliases.create_email_alias(
                Map.merge(attrs, %{
                  user_id: connection.user.id,
                  address: local <> "@" <> stored_domain
                })
              )
          end

        _ ->
          error("INVALID_ARGUMENT", "Supply a verified custom domain when choosing a local part")
      end

    alias_result(result)
  end

  defp execute(connection, "list_verified_domains", args) do
    domains =
      connection.user
      |> Domain.list_custom_domains()
      |> Enum.filter(&Domain.fully_verified?/1)
      |> Enum.drop(offset(args))
      |> Enum.take(11)

    {:ok,
     %{domains: Enum.take(domains, 10) |> Enum.map(& &1.domain), has_more: length(domains) > 10}}
  end

  defp execute(connection, name, args) do
    email_alias =
      connection.user
      |> Aliases.aliases_query()
      |> Repo.get_by(address: String.downcase(args["address"]))

    case {email_alias, name} do
      {nil, _} ->
        error("ALIAS_NOT_FOUND", "Alias not found")

      {email_alias, "get_alias"} ->
        {:ok, alias_data(email_alias)}

      {email_alias, "edit_alias"} ->
        attrs = Map.take(args, ["title", "notes", "enabled"])

        if map_size(attrs) == 0,
          do: error("INVALID_ARGUMENT", "Supply a title, notes or enabled status to edit"),
          else: alias_result(Aliases.update_email_alias(email_alias, attrs))
    end
  end

  defp alias_result({:ok, email_alias}), do: {:ok, alias_data(email_alias)}

  defp alias_result({:error, :inactive_user}),
    do: error("ACCOUNT_INACTIVE", "Account is inactive")

  defp alias_result({:error, :free_limit_reached}),
    do:
      error(
        "ALIAS_LIMIT_REACHED",
        "Your account's alias limit has been reached. Upgrade for more aliases: #{Shroud.Mcp.issuer()}/settings/billing"
      )

  defp alias_result({:error, %Ecto.Changeset{} = changeset}) do
    if Enum.any?(changeset.errors, fn {field, {_message, opts}} ->
         field == :address and opts[:constraint] == :unique
       end) do
      error(
        "ALIAS_ALREADY_EXISTS",
        "This alias address already exists, including as a disabled alias. Choose a different local part or edit the existing alias.",
        %{address: Ecto.Changeset.get_field(changeset, :address)}
      )
    else
      error("INVALID_ARGUMENT", "Alias could not be saved; check the address and metadata")
    end
  end

  defp alias_result({:error, _, _} = result), do: result

  defp alias_data(email_alias) do
    email_alias
    |> Map.take([:address, :title, :notes, :enabled])
    |> Map.put(:created_at, NaiveDateTime.to_iso8601(email_alias.inserted_at) <> "Z")
  end

  defp error(code, message, details \\ %{}),
    do: {:error, message, Map.put(details, :error_code, code)}

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

  defp tool(name, title, description, input, output, read_only, destructive) do
    error_output =
      object(
        %{
          error_code: %{type: "string", minLength: 1},
          address: %{type: "string"},
          required_scopes: %{type: "array", items: %{type: "string"}}
        },
        [:error_code]
      )

    %{
      name: name,
      title: title,
      description: description,
      inputSchema: input,
      outputSchema: %{type: "object", anyOf: [output, error_output]},
      annotations: %{readOnlyHint: read_only, destructiveHint: destructive, openWorldHint: false}
    }
  end
end
