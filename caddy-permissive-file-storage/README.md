# caddy-permissive-file-storage

This is a slight modification of Caddy's file storage plugin. The only difference is that files are stored with slightly more open permissions, so that other services can read Caddy's SSL certificates.

> [!WARNING]
> These permissions also make TLS private keys readable to every user or process
> that can access the storage volume. Use this plugin only on a volume shared
> exclusively with trusted services; never expose that volume to untrusted users,
> containers, or tenants.

Use it by configuring it in your Caddyfile, e.g.

```
{
  storage permissive_file_storage {
    root "/tmp/caddy"
  }
  http_port 8080
  https_port 4443
}

localhost {
  tls internal
  respond "ok" 200
}
```

This is used for certificate provisioning in [Shroud.email](https://shroud.email/).

## Development

### Tests

An end-to-end test builds Caddy with this plugin, runs it with `tls internal`,
and asserts that cert/key files are written with world-readable permissions
(`0644` files, `0755` directories).

```bash
bash test/e2e.sh
```

The test fails if [`xcaddy`](https://github.com/caddyserver/xcaddy) is not
installed or ports 8080/9443 are in use. CI runs it on pull requests and on
pushes to `main` that change this module or its deployment workflow.
