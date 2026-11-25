//go:build vpro_headless

package interchange

import (
	"context"
	"errors"
)

func parseVenusAccessArchive(_ context.Context, _, _ string) (venusNormalizedArchive, error) {
	return venusNormalizedArchive{}, errors.New("Microsoft Access VENUS import (.mdb/.accdb) is unavailable in headless mode")
}
