defmodule Shroud.Repo.Migrations.RegisterExtensionOauthClient do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO oauth_clients (
      id, name, secret, private_key, redirect_uris, supported_grant_types,
      pkce, public_refresh_token, public_revoke, authorize_scope,
      authorization_code_ttl, access_token_ttl, refresh_token_ttl,
      token_endpoint_auth_methods, metadata, inserted_at, updated_at
    ) VALUES (
      'fc4258c1-58a9-4865-8f2f-e78345dcfd46', 'Shroud.email browser extension', '', '',
      ARRAY['https://app.shroud.email/oauth/extension/callback'],
      ARRAY['authorization_code', 'refresh_token', 'revoke'],
      true, true, true, false, 300, 3600, 7776000, ARRAY['none'],
      '{"name":"Shroud.email browser extension","resource_path":"/api/v1","registered":true}',
      CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    )
    ON CONFLICT (id) DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM oauth_clients WHERE id = 'fc4258c1-58a9-4865-8f2f-e78345dcfd46'")
  end
end
