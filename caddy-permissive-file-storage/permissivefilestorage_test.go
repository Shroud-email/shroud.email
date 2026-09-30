package permissivefilestorage

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"

	"github.com/caddyserver/certmagic"
)

func TestStoreSetsExplicitModes(t *testing.T) {
	oldUmask := syscall.Umask(0077)
	t.Cleanup(func() { syscall.Umask(oldUmask) })

	root := filepath.Join(t.TempDir(), "storage")
	if err := os.Mkdir(root, 0700); err != nil {
		t.Fatal(err)
	}
	nested := filepath.Join(root, "certificates", "example")
	if err := os.MkdirAll(nested, 0700); err != nil {
		t.Fatal(err)
	}
	filename := filepath.Join(nested, "certificate.pem")
	if err := os.WriteFile(filename, []byte("old"), 0600); err != nil {
		t.Fatal(err)
	}

	storage := &CertmagicStorage{FileStorage: certmagicFileStorage(root)}
	if err := storage.Store(context.Background(), "certificates/example/certificate.pem", []byte("new")); err != nil {
		t.Fatalf("Store: %v", err)
	}

	for _, path := range []string{root, filepath.Join(root, "certificates"), nested} {
		assertMode(t, path, 0755)
	}
	assertMode(t, filename, 0644)
}

func TestStoreSetsModesOnNewPathsWithRestrictiveUmask(t *testing.T) {
	oldUmask := syscall.Umask(0077)
	t.Cleanup(func() { syscall.Umask(oldUmask) })

	root := filepath.Join(t.TempDir(), "storage")
	storage := &CertmagicStorage{FileStorage: certmagicFileStorage(root)}
	if err := storage.Store(context.Background(), "new/nested/value", []byte("value")); err != nil {
		t.Fatalf("Store: %v", err)
	}

	for _, path := range []string{root, filepath.Join(root, "new"), filepath.Join(root, "new", "nested")} {
		assertMode(t, path, 0755)
	}
	assertMode(t, filepath.Join(root, "new", "nested", "value"), 0644)
}

func TestStoreReadersSeeOnlyCompleteValues(t *testing.T) {
	root := t.TempDir()
	storage := &CertmagicStorage{FileStorage: certmagicFileStorage(root)}
	key := "certificates/example/certificate.pem"
	oldValue := bytes.Repeat([]byte("a"), 256*1024)
	newValue := bytes.Repeat([]byte("b"), 256*1024)
	if err := storage.Store(context.Background(), key, oldValue); err != nil {
		t.Fatal(err)
	}

	filename := filepath.Join(root, filepath.FromSlash(key))
	stop := make(chan struct{})
	errCh := make(chan string, 1)
	var readers sync.WaitGroup
	for range 4 {
		readers.Add(1)
		go func() {
			defer readers.Done()
			for {
				select {
				case <-stop:
					return
				default:
				}
				value, err := os.ReadFile(filename)
				if err != nil {
					select {
					case errCh <- err.Error():
					default:
					}
					return
				}
				if !bytes.Equal(value, oldValue) && !bytes.Equal(value, newValue) {
					select {
					case errCh <- "reader observed a partial or corrupt value":
					default:
					}
					return
				}
			}
		}()
	}
	for range 20 {
		if err := storage.Store(context.Background(), key, newValue); err != nil {
			t.Fatal(err)
		}
		if err := storage.Store(context.Background(), key, oldValue); err != nil {
			t.Fatal(err)
		}
	}
	close(stop)
	readers.Wait()
	select {
	case message := <-errCh:
		t.Fatalf("reader observed a non-atomic store: %s", message)
	default:
	}
}

func TestStoreCleansUpTempFileAfterRenameFailure(t *testing.T) {
	root := t.TempDir()
	destination := filepath.Join(root, "value")
	if err := os.Mkdir(destination, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(destination, "child"), nil, 0644); err != nil {
		t.Fatal(err)
	}

	storage := &CertmagicStorage{FileStorage: certmagicFileStorage(root)}
	if err := storage.Store(context.Background(), "value", []byte("new")); err == nil {
		t.Fatal("Store succeeded replacing a non-empty directory")
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".value.tmp-") {
			t.Errorf("temporary file was not removed: %s", entry.Name())
		}
	}
}

func certmagicFileStorage(root string) certmagic.FileStorage {
	return certmagic.FileStorage{Path: root}
}

func assertMode(t *testing.T, path string, want os.FileMode) {
	t.Helper()
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != want {
		t.Errorf("%s mode = %04o, want %04o", path, got, want)
	}
}
