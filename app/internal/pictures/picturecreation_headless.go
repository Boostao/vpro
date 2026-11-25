//go:build vpro_headless

package pictures

import (
	"context"
	"errors"
)

type pictureCreationNativeOwner struct{}

func (pictureCreationNativeOwner) windowID() uint { return 0 }

func currentPictureCreationOwner(ctx context.Context) (pictureCreationNativeOwner, error) {
	if ctx == nil {
		return pictureCreationNativeOwner{}, errors.New("file selection requires an active desktop window")
	}
	if err := ctx.Err(); err != nil {
		return pictureCreationNativeOwner{}, err
	}
	return pictureCreationNativeOwner{}, errors.New("file selection requires an active desktop window; enter a file path directly when running in a browser")
}

func chooseNativePictureFile(ctx context.Context) (string, error) {
	if ctx == nil {
		return "", errors.New("file selection requires an active desktop window")
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	return "", errors.New("file selection requires an active desktop window; enter a file path directly when running in a browser")
}
