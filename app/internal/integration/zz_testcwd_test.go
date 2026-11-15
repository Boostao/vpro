package integration

import (
	"os"

	"github.com/boostao/vpro/app/resources"
)

func init() {
	_ = os.Chdir(resources.RepoRoot())
}
