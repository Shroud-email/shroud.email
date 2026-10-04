defmodule Shroud.Repo.Migrations.RegisterOfficialOauthClients do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO oauth_clients (
      id, name, secret, private_key, redirect_uris, supported_grant_types,
      pkce, public_refresh_token, public_revoke, authorize_scope,
      authorization_code_ttl, access_token_ttl, refresh_token_ttl,
      token_endpoint_auth_methods, metadata, inserted_at, updated_at
    )
    SELECT id::uuid, id, '', '', ARRAY[callback],
      ARRAY['authorization_code', 'refresh_token', 'revoke'],
      true, true, true, false, 300, 3600, 7776000, ARRAY['none'],
      jsonb_build_object('name', display_name, 'resource_path', resource_path, 'registered', true),
      CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    FROM (VALUES
      ('3dab4011-1a87-453f-9b6d-c8e12a41c892', 'Shroud.email mobile', '/api/v1',
       'https://app.shroud.email/oauth/callback'),
      ('7b705cee-124c-4abe-827f-d61c030c32c0', 'ChatGPT', '/mcp',
       'https://chatgpt.com/connector_platform_oauth_redirect')
    ) AS clients(id, display_name, resource_path, callback)
    ON CONFLICT (id) DO UPDATE SET
      name = EXCLUDED.name,
      secret = EXCLUDED.secret,
      private_key = EXCLUDED.private_key,
      redirect_uris = EXCLUDED.redirect_uris,
      supported_grant_types = EXCLUDED.supported_grant_types,
      pkce = EXCLUDED.pkce,
      public_refresh_token = EXCLUDED.public_refresh_token,
      public_revoke = EXCLUDED.public_revoke,
      authorize_scope = EXCLUDED.authorize_scope,
      authorization_code_ttl = EXCLUDED.authorization_code_ttl,
      access_token_ttl = EXCLUDED.access_token_ttl,
      refresh_token_ttl = EXCLUDED.refresh_token_ttl,
      token_endpoint_auth_methods = EXCLUDED.token_endpoint_auth_methods,
      metadata = EXCLUDED.metadata,
      updated_at = EXCLUDED.updated_at
    """)
  end

  def down do
    execute("""
    DELETE FROM oauth_clients
    WHERE id IN ('3dab4011-1a87-453f-9b6d-c8e12a41c892', '7b705cee-124c-4abe-827f-d61c030c32c0')
    """)
  end
end
