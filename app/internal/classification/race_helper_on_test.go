//go:build race

package classification

func isRaceDetectorActive() bool {
	return true
}
