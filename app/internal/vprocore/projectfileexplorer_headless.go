//go:build vpro_headless

package vprocore

import (
	"context"
	"errors"
)

func chooseNativeOpenFileWithFilters(ctx context.Context, _ string, _ []nativeFileFilter) (string, error) {
	if ctx == nil {
		return "", errors.New("file selection requires an active desktop window")
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return "", errors.New("file selection requires an active desktop window; enter a file path directly when running in a browser")
}

func chooseNativeSaveFileWithFilters(ctx context.Context, _, _, _ string, _ []nativeFileFilter) (string, error) {
	if ctx == nil {
		return "", errors.New("file selection requires an active desktop window")
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return "", errors.New("file selection requires an active desktop window; enter a file path directly when running in a browser")
}

func openPathInSystemFileExplorer(_ string, _ bool) error {
	return errors.New("file explorer is unavailable in headless mode")
}
