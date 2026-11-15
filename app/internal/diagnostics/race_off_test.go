//go:build !race

package diagnostics

import (
	"os"
	"time"
)

var synthesisLatencyBudget = func() time.Duration {
	if os.Getenv("CI") == "true" {
		return 100 * time.Millisecond
	}
	return 50 * time.Millisecond
}()
