//go:build !vpro_headless

package lifecycle

import (
	"log"

	"github.com/wailsapp/wails/v3/pkg/application"
)

func init() {
	application.RegisterEvent[string](CloseRequestEvent)
}

// HandleWindowClosing — RegisterHook runs synchronously before Wails' closing listeners. Always
// cancel this window event: ConfirmClose exits through the separate App.Quit.
func (s *CloseService) HandleWindowClosing(event *application.WindowEvent) {
	event.Cancel()
	if err := s.requestClose(); err != nil {
		log.Printf("Native close remains blocked: %v", err)
	}
}
