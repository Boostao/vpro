package vprocore

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestPictureNativeChooserOwnerUsesPlainFileSelectionCopy(t *testing.T) {
	//lint:ignore SA1012 intentional nil-context guard test
	if _, _, err := PictureNativeChooserOwner(nil); err == nil {
		t.Fatal("expected error on nil context")
	} else if strings.Contains(strings.ToLower(err.Error()), "picture selection") || !strings.Contains(strings.ToLower(err.Error()), "file selection") {
		t.Fatalf("expected plain file selection message on nil context, got %q", err.Error())
	}

	if _, _, err := PictureNativeChooserOwner(context.Background()); err == nil {
		t.Fatal("expected error when no native window is attached to context")
	} else if strings.Contains(strings.ToLower(err.Error()), "picture selection") || !strings.Contains(strings.ToLower(err.Error()), "file selection") {
		t.Fatalf("expected plain file selection message in non-window/server context, got %q", err.Error())
	}

	cancelled, cancel := context.WithCancel(context.Background())
	cancel()
	if _, _, err := PictureNativeChooserOwner(cancelled); !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled to propagate unchanged, got %v", err)
	}
}
