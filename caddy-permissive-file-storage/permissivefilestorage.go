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
	directory := filepath.Dir(filename)
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}

	// MkdirAll and CreateTemp apply the process umask when creating paths and do
	// not update permissions on paths that already exist. Set the requested
	// permissions explicitly so storage remains readable in both cases.
	root := filepath.Clean(fs.Path)
	for current := directory; ; current = filepath.Dir(current) {
		if err := os.Chmod(current, 0755); err != nil {
			return err
		}
		if current == root {
			break
		}
		parent := filepath.Dir(current)
		if parent == current {
			break
		}
	}

	temp, err := os.CreateTemp(directory, "."+filepath.Base(filename)+".tmp-*")
	if err != nil {
		return err
	}
	tempName := temp.Name()
	defer os.Remove(tempName)

	if err := temp.Chmod(0644); err != nil {
		temp.Close()
		return err
	}
	if _, err := temp.Write(value); err != nil {
		temp.Close()
		return err
	}
	if err := temp.Close(); err != nil {
		return err
	}
	return os.Rename(tempName, filename)
}
