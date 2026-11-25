//go:build !vpro_headless

package interchange

import (
	"context"
	"fmt"
	"strings"

	"github.com/boostao/vpro/app/internal/accessreader"
)

func parseVenusAccessArchive(ctx context.Context, resolvedPath, shaHex string) (venusNormalizedArchive, error) {
	db, err := accessreader.Open(resolvedPath)
	if err != nil {
		return venusNormalizedArchive{}, fmt.Errorf("open VENUS Access database: %w", err)
	}
	tables, err := db.Tables()
	if err != nil {
		return venusNormalizedArchive{}, err
	}
	byLower := map[string]string{}
	for _, t := range tables {
		if !t.Linked {
			byLower[strings.ToLower(t.Name)] = t.Name
		}
	}

	readStringTable := func(candidates ...string) ([]map[string]string, bool, error) {
		for _, cand := range candidates {
			actual, ok := byLower[strings.ToLower(cand)]
			if !ok {
				continue
			}
			cols, rows, err := db.ReadAll(actual)
			if err != nil {
				return nil, false, err
			}
			adaptedIdx, adaptedRows, err := adaptAccessRows(ctx, cols, rows)
			if err != nil {
				return nil, false, err
			}
			out := make([]map[string]string, 0, len(adaptedRows))
			for _, r := range adaptedRows {
				m := make(map[string]string, len(adaptedIdx))
				for k, idx := range adaptedIdx {
					if r[idx] != nil {
						m[k] = strings.TrimSpace(fmt.Sprint(r[idx]))
					}
				}
				out = append(out, m)
			}
			return out, true, nil
		}
		return nil, false, nil
	}

	return parseVenusAccessTables(byLower, readStringTable, shaHex)
}
