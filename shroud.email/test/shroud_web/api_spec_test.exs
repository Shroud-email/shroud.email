defmodule ShroudWeb.ApiSpecTest do
  use ExUnit.Case, async: true
  import OpenApiSpex.TestAssertions, only: [assert_raw_schema: 2]
  alias ShroudWeb.Api.V1.Schemas

  test "all and only public v1 routes are annotated with stable operation IDs" do
    spec = ShroudWeb.ApiSpec.spec()

    operations =
      for {path, item} <- spec.paths,
          {method, %OpenApiSpex.Operation{} = operation} <- Map.from_struct(item),
          do: {{path, method}, operation.operationId}

    assert Map.new(operations) == %{
             {"/api/v1/token", :post} => "createToken",
             {"/api/v1/me", :get} => "getProfile",
             {"/api/v1/alias-capabilities", :get} => "getAliasCapabilities",
             {"/api/v1/aliases", :get} => "listAliases",
             {"/api/v1/aliases", :post} => "createAlias",
             {"/api/v1/aliases/{address}", :get} => "getAlias",
             {"/api/v1/aliases/{address}", :patch} => "updateAlias",
             {"/api/v1/aliases/{address}", :delete} => "deleteAlias",
             {"/api/v1/domains", :get} => "listDomains"
           }

    routes =
      ShroudWeb.Router.__routes__() |> Enum.filter(&String.starts_with?(&1.path, "/api/v1/"))

    assert length(routes) == length(operations)

    for route <- routes do
      assert route.plug.open_api_operation(route.plug_opts)
    end

    assert spec.security == [%{"bearerAuth" => []}]
    assert [%{url: "https://app.shroud.email"}] = spec.servers
    assert spec.components.securitySchemes["bearerAuth"].scheme == "bearer"
    assert spec.paths["/api/v1/token"].post.security == []

    for {path, item} <- spec.paths,
        path != "/api/v1/token",
        {_, %OpenApiSpex.Operation{} = operation} <- Map.from_struct(item) do
      assert operation.security == nil
    end

    assert spec.paths["/api/v1/aliases/{address}"].delete.responses[204].content == nil
  end

  test "optional create body, selected domain, local name requiring domain and nullable metadata" do
    assert ShroudWeb.ApiSpec.spec().paths["/api/v1/aliases"].post.requestBody.required == false

    for params <- [
          %{},
          %{title: "Acme"},
          %{title: nil, notes: nil},
          %{domain: "example.com"},
          %{local_part: "myemail", domain: "example.com"}
        ] do
      assert_raw_schema(params, Schemas.create_alias())
    end

    for schema <- [Schemas.create_alias(), Schemas.update_alias(), Schemas.email_alias()] do
      assert schema.properties.title.nullable
      assert schema.properties.notes.nullable
    end

    assert_raw_schema(%{title: nil, notes: nil, enabled: false}, Schemas.update_alias())

    schema =
      Schemas.create_alias() |> OpenApiSpex.OpenApi.to_map() |> Jason.encode!() |> Jason.decode!()

    resolved = ExJsonSchema.Schema.resolve(schema)
    assert :ok = ExJsonSchema.Validator.validate(resolved, %{"domain" => "example.com"})
    assert {:error, _} = ExJsonSchema.Validator.validate(resolved, %{"local_part" => "shop"})
  end

  test "every documented JSON example conforms to its schema" do
    spec = ShroudWeb.ApiSpec.spec()

    for {_, item} <- spec.paths,
        {_, %OpenApiSpex.Operation{} = operation} <- Map.from_struct(item) do
      contents =
        for {_, response} <- operation.responses, {_, media} <- response.content || %{}, do: media

      contents =
        contents ++
          if operation.requestBody, do: Map.values(operation.requestBody.content), else: []

      for media <- contents do
        example = if is_nil(media.example), do: media.schema.example, else: media.example
        refute is_nil(example), "Missing JSON example for #{operation.operationId}"
        assert_raw_schema(example, media.schema)
      end
    end
  end
end
