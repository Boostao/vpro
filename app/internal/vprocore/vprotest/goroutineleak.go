package vprotest

import (
	"bytes"
	"runtime"
	"runtime/pprof"
	"testing"
	"time"
)

// AssertNoGoroutineLeak checks Go 1.27's experimental goroutineleak profile
// when enabled (GOEXPERIMENT=goroutineleakprofile) and fails if any leaked
// goroutines are detected after cleanup.
func AssertNoGoroutineLeak(t *testing.T) {
	t.Helper()
	t.Cleanup(func() {
		runtime.GC()
		time.Sleep(10 * time.Millisecond)
		prof := pprof.Lookup("goroutineleak")
		if prof == nil {
			return
		}
		if prof.Count() > 0 {
			var buf bytes.Buffer
			_ = prof.WriteTo(&buf, 2)
			t.Fatalf("detected %d leaked goroutine(s):\n%s", prof.Count(), buf.String())
		}
	})
}
