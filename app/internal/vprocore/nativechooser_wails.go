//go:build !vpro_headless

package vprocore

import (
	"context"
	"errors"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func PictureNativeChooserOwner(ctx context.Context) (*application.App, *application.WebviewWindow, error) {
	if ctx == nil {
		return nil, nil, errors.New("file selection requires an active desktop window")
	}
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	window, ok := ctx.Value(application.WindowKey).(*application.WebviewWindow)
	if !ok || window == nil || window.NativeWindow() == nil {
		return nil, nil, errors.New("file selection requires an active desktop window; enter a file path directly when running in a browser")
	}
	app := application.Get()
	if app == nil || app.Window == nil || app.Dialog == nil {
		return nil, nil, errors.New("file selection requires the active desktop application")
	}
	registered, present := app.Window.GetByID(window.ID())
	native, ok := registered.(*application.WebviewWindow)
	if !present || !ok || native != window {
		return nil, nil, errors.New("file selection window is no longer active; please try again")
	}
	return app, window, nil
}
