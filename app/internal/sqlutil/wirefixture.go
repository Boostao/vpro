package sqlutil

import "github.com/boostao/vpro/app/internal/listcatalog"

// ReadWireFixture reads a JSON wire fixture from path, transparently gunzipping
// .gz files and falling back to path+".gz" when the plain .json file is absent.
func ReadWireFixture(path string) ([]byte, error) {
	return listcatalog.ReadFixture(path)
}
