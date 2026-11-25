//go:build !vpro_headless

package vprocore

import (
	"context"
	"errors"
	"fmt"
)

func chooseNativeOpenFileWithFilters(ctx context.Context, title string, filters []nativeFileFilter) (string, error) {
	app, window, err := PictureNativeChooserOwner(ctx)
	if err != nil {
		return "", err
	}
	handle := window.NativeWindow()
	if handle == nil {
		return "", errors.New("native file selection window closed before opening its dialog")
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	selected, err := promptNativeOpenFileWithTitle(app, window, handle, title, filters)
	if err != nil {
		return "", fmt.Errorf("native file selection failed: %w", err)
	}
	currentApp, current, err := PictureNativeChooserOwner(ctx)
	if err != nil {
		return "", err
	}
	if currentApp != app || current != window || current.NativeWindow() != handle {
		return "", errors.New("native file selection owner changed while the dialog was open")
	}
	return selected, nil
}

func chooseNativeSaveFileWithFilters(ctx context.Context, title, defaultFileName, defaultExt string, filters []nativeFileFilter) (string, error) {
	app, window, err := PictureNativeChooserOwner(ctx)
	if err != nil {
		return "", err
	}
	handle := window.NativeWindow()
	if handle == nil {
		return "", errors.New("native file save window closed before opening its dialog")
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	selected, err := promptNativeSaveFileWithTitle(app, window, handle, title, defaultFileName, defaultExt, filters)
	if err != nil {
		return "", fmt.Errorf("native file save selection failed: %w", err)
	}
	currentApp, current, err := PictureNativeChooserOwner(ctx)
	if err != nil {
		return "", err
	}
	if currentApp != app || current != window || current.NativeWindow() != handle {
		return "", errors.New("native file save owner changed while the dialog was open")
	}
	return selected, nil
}
