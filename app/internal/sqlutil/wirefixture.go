package sqlutil

import (
	"errors"
	"os"
	"path/filepath"

	"github.com/boostao/vpro/app/internal/listcatalog"
	"github.com/boostao/vpro/app/resources"
)

// ReadWireFixture reads a JSON wire fixture from path, transparently gunzipping
// .gz files, falling back to path+".gz", and resolving repo-relative paths via
// resources.RepoRoot() so package tests remain CWD-independent without os.Chdir.
func ReadWireFixture(path string) ([]byte, error) {
	data, err := listcatalog.ReadFixture(path)
	if err == nil || filepath.IsAbs(path) || !errors.Is(err, os.ErrNotExist) {
		return data, err
	}
	if root := resources.RepoRoot(); root != "" {
		if repoData, repoErr := listcatalog.ReadFixture(filepath.Join(root, path)); repoErr == nil {
			return repoData, nil
		}
	}
	return nil, err
}
