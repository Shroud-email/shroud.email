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
        Authorization header: `Authorization: Bearer c2hyb3VkLmVtYWlsIHRva2VuIDotKQ==`.
        Create a token with `/api/v1/token`. Tokens give access to your account: keep them secret!
        Alias and domain operations require a confirmed account.
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
