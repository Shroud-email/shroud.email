defmodule ShroudWeb.ApiSpec do
  @behaviour OpenApiSpex.OpenApi
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, SecurityScheme, Server}

  @impl true
  def spec do
    %OpenApi{
      info: %Info{
        title: "Shroud.email API",
        version: "v1",
        description: """
        For hosted Shroud.email, use `https://app.shroud.email`. If you're self-hosting,
        replace this with your own instance's domain.

        All requests except token creation must include a bearer token in the standard
        Authorization header: `Authorization: Bearer <token>`.
        Public clients use `/oauth/authorize` and `/oauth/token` with PKCE S256 and
        resource `https://app.shroud.email/api/v1` (the instance URL for self-hosting).
        Account session tokens from `/api/v1/token` are also accepted.
        Keep all tokens secret. All authenticated operations require a confirmed account.
        Missing or invalid credentials return 401; insufficient OAuth scope returns 403.

        OAuth permissions: GET aliases requires aliases:read; POST aliases requires
        aliases:create; PATCH aliases requires aliases:edit; DELETE aliases requires
        aliases:delete; GET domains requires domains:read; GET me requires profile:read.
        Mutation scopes also require aliases:read at consent. MCP tokens cannot access this API.
        """
      },
      servers: [%Server{url: "https://app.shroud.email"}],
      security: [%{"bearerAuth" => []}],
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{type: "http", scheme: "bearer"}
        }
      },
      paths: Paths.from_router(ShroudWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
