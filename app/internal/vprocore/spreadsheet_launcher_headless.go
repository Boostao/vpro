//go:build vpro_headless

package vprocore

import "context"

func openSpreadsheetPlatform(ctx context.Context, _, _ string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	return ErrSpreadsheetLaunchUnavailableHeadless
}
