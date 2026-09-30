package permissivefilestorage

import (
	"context"
	"os"
	"path/filepath"

	"github.com/caddyserver/caddy/v2"
	"github.com/caddyserver/caddy/v2/modules/filestorage"
	"github.com/caddyserver/certmagic"
)

func init() {
	caddy.RegisterModule(PermissiveStorage{})
}

type CertmagicStorage struct {
	certmagic.FileStorage
}

type PermissiveStorage struct {
	filestorage.FileStorage
}

func (PermissiveStorage) CaddyModule() caddy.ModuleInfo {
	return caddy.ModuleInfo{
		ID:  "caddy.storage.permissive_file_storage",
		New: func() caddy.Module { return new(PermissiveStorage) },
	}
}

// CertMagicStorage converts s to a certmagic.Storage instance.
func (s PermissiveStorage) CertMagicStorage() (certmagic.Storage, error) {
	return &CertmagicStorage{
		FileStorage: certmagic.FileStorage{
			Path: s.Root,
		},
	}, nil
}

// Override Store to use globally-readable permissions
func (fs *CertmagicStorage) Store(_ context.Context, key string, value []byte) error {
	filename := fs.Filename(key)
	err := os.MkdirAll(filepath.Dir(filename), 0755)
	if err != nil {
		return err
	}
	return os.WriteFile(filename, value, 0644)
}
