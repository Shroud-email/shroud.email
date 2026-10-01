defmodule Shroud.Mcp.Tools do
  @moduledoc "The bounded alias-management surface exposed to MCP clients."
  import Ecto.Query
  alias ExMCP.Content.SchemaPolicy
  alias Shroud.{Aliases, Domain, Repo}

  def list do
    address = string("Exact alias address", 320)
    title = string("Alias label; not an email address", 255)
    notes = string("Alias notes. Do not store passwords or verification codes.", 2000, 0)

    page = %{
      type: "integer",
      minimum: 1,
      maximum: 1000,
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
        "find_aliases",
        "Find aliases",
        "Find aliases by an address or label fragment in the connected account. Returns up to ten candidates without notes; clarify ambiguous matches rather than guessing. A nonblank query is required, not a whole-account export.",
        "aliases:read",
        object(
          %{
            query: string("Address or label fragment", 255),
            enabled: %{type: "boolean"},
            page: page
          },
          [:query]
        ),
        object(
          %{
            aliases: %{
              type: "array",
              items:
                object(Map.drop(alias_output.properties, [:notes]), [:address, :title, :enabled])
            },
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
        "Read the label, notes and enabled status of one exact alias owned by the connected account. Does not retrieve email content or forwarding destinations.",
        "aliases:read",
        object(%{address: address}, [:address]),
        alias_output,
        true,
        false
      ),
      tool(
        "create_alias",
        "Create a labelled alias",
        "Create a random alias with a label and optional notes. To use an existing verified custom domain supply both domain and local_part. Retrying creates another alias; no email is sent and no signup is performed.",
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
        "Edit alias label or notes",
        "Replace the label and/or notes of one exact alias. An empty string clears a field. Does not change the address, enabled status or forwarding destination.",
        "aliases:edit",
        object(
          %{
            address: address,
            title: string("Replacement label; empty clears it", 255, 0),
            notes: notes
          },
          [:address]
        ),
        alias_output,
        false,
        true
      ),
      tool(
        "enable_alias",
        "Re-enable an alias",
        "Re-enable forwarding for one exact alias owned by the connected account. Does not change its address or forwarding destination.",
        "aliases:status",
        object(%{address: address}, [:address]),
        alias_output,
        false,
        false
      ),
      tool(
        "disable_alias",
        "Disable an alias",
        "Disable forwarding for one exact alias owned by the connected account. Takes effect immediately and stops all forwarding, including password-reset emails. Does not delete the alias or change its forwarding destination; it can be re-enabled later.",
        "aliases:status",
        object(%{address: address}, [:address]),
        alias_output,
        false,
        true
      ),
      tool(
        "list_verified_domains",
        "List verified custom domains",
        "List up to ten existing, currently verified custom domain names in the connected account, for alias creation. Does not add domains, return DNS secrets, or initiate billing.",
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
      nil -> {:error, "Unknown tool"}
      _ -> {:error, "Invalid tool arguments"}
    end
  end

  defp execute(connection, "find_aliases", args) do
    escaped =
      args["query"]
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    pattern = "%" <> escaped <> "%"

    query =
      connection.user
      |> Aliases.aliases_query()
      |> where([a], ilike(a.address, ^pattern) or ilike(a.title, ^pattern))

    query =
      if Map.has_key?(args, "enabled"),
        do: where(query, [a], a.enabled == ^args["enabled"]),
        else: query

    entries =
      query |> order_by([a], desc: a.id) |> limit(11) |> offset(^offset(args)) |> Repo.all()

    {:ok,
     %{
       aliases: Enum.take(entries, 10) |> Enum.map(&(alias_data(&1) |> Map.delete(:notes))),
       has_more: length(entries) > 10
     }}
  end

  defp execute(connection, "create_alias", args) do
    metadata = %{title: args["title"]} |> maybe_notes(args)

    result =
      case {args["domain"], args["local_part"]} do
        {nil, nil} ->
          Aliases.create_random_email_alias(connection.user, metadata)

        {domain, local} when is_binary(domain) and is_binary(local) ->
          verified =
            Domain.list_custom_domains(connection.user)
            |> Enum.find(
              &(String.downcase(&1.domain) == String.downcase(domain) and
                  Domain.fully_verified?(&1))
            )

          # Keep the stored domain spelling for the context's exact domain lookup;
          # the alias changeset normalizes the address only after association.
          with %{domain: stored_domain} <- verified,
               true <- Regex.match?(~r/^[A-Za-z0-9.!#$%&'*+\/=?^`{|}~-]+$/, local),
               address = local <> "@" <> stored_domain,
               {:ok, [{:undefined, _}]} <- :smtp_util.parse_rfc5322_addresses(address) do
            Aliases.create_email_alias(
              Map.merge(metadata, %{user_id: connection.user_id, address: address})
            )
          else
            _ -> {:error, :invalid_domain}
          end

        _ ->
          {:error, :invalid_domain}
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
        {:error, "Alias not found"}

      {email_alias, "get_alias"} ->
        {:ok, alias_data(email_alias)}

      {email_alias, "edit_alias"} ->
        attrs = Map.take(args, ["title", "notes"])

        if map_size(attrs) == 0,
          do: {:error, "Supply a label or notes to edit"},
          else: alias_result(Aliases.update_email_alias(email_alias, attrs))

      {email_alias, "enable_alias"} ->
        alias_result(Aliases.update_email_alias(email_alias, %{enabled: true}))

      {email_alias, "disable_alias"} ->
        alias_result(Aliases.update_email_alias(email_alias, %{enabled: false}))
    end
  end

  defp alias_result({:ok, email_alias}), do: {:ok, alias_data(email_alias)}
  defp alias_result({:error, :inactive_user}), do: {:error, "Account is inactive"}

  defp alias_result({:error, :free_limit_reached}),
    do: {:error, "Your account's alias limit has been reached"}

  defp alias_result({:error, :invalid_domain}),
    do: {:error, "Supply both a valid local part and an existing verified custom domain"}

  defp alias_result({:error, %Ecto.Changeset{}}),
    do: {:error, "Alias could not be saved; check the address and metadata"}

  defp alias_data(email_alias), do: Map.take(email_alias, [:address, :title, :notes, :enabled])

  defp maybe_notes(metadata, args),
    do:
      if(Map.has_key?(args, "notes"),
        do: Map.put(metadata, :notes, args["notes"]),
        else: metadata
      )

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
