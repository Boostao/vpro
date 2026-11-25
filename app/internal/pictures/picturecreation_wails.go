//go:build !vpro_headless

package pictures

import (
	"context"
	"errors"
	"unsafe"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/wailsapp/wails/v3/pkg/application"
)

// Request contexts are RPC-owned and must never be retained by a capability.
type pictureCreationNativeOwner struct {
	app    *application.App
	window *application.WebviewWindow
	handle unsafe.Pointer
}

func (o pictureCreationNativeOwner) windowID() uint {
	if o.window != nil {
		return o.window.ID()
	}
	return 0
}

func currentPictureCreationOwner(ctx context.Context) (pictureCreationNativeOwner, error) {
	app, window, err := vprocore.PictureNativeChooserOwner(ctx)
	if err != nil {
		return pictureCreationNativeOwner{}, err
	}
	handle := window.NativeWindow()
	if handle == nil {
		return pictureCreationNativeOwner{}, errors.New("picture creation native request window closed")
	}
	return pictureCreationNativeOwner{app, window, handle}, nil
}
