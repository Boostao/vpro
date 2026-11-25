//go:build vpro_headless

package main

import (
	"os/exec"
	"strings"
	"testing"
)

const testBuildTags = "vpro_headless"

func TestHeadlessZeroWailsAndAccessReaderDeps(t *testing.T) {
	cmd := exec.Command("go", "list", "-tags", "vpro_headless", "-deps", "./cmd/vpro-web")
	cmd.Dir = "../.."
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("go list -tags vpro_headless -deps ./cmd/vpro-web failed: %v\n%s", err, string(out))
	}

	var forbidden []string
	for _, line := range strings.Split(string(out), "\n") {
		dep := strings.TrimSpace(line)
		if dep == "" {
			continue
		}
		if strings.Contains(dep, "github.com/wailsapp/wails") ||
			strings.Contains(dep, "github.com/boostao/vpro/app/internal/accessreader") {
			forbidden = append(forbidden, dep)
		}
	}
	if len(forbidden) > 0 {
		t.Fatalf("cmd/vpro-web must have zero transitive Wails v3 or accessreader imports under -tags vpro_headless; found:\n%s",
			strings.Join(forbidden, "\n"))
	}
}
