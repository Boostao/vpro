package main

import (
	"context"
	"errors"
	"log"
	"path/filepath"
	"sync"

	cloudsyncpkg "github.com/boostao/vpro/app/internal/cloudsync"
	lifecyclepkg "github.com/boostao/vpro/app/internal/lifecycle"
	spatialpkg "github.com/boostao/vpro/app/internal/spatial"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

func noopRelease() {}

type runtimeBundle struct {
	refs           int
	retired        bool
	closed         bool
	projects       *vprocorepkg.ProjectService
	working        *vprocorepkg.WorkingUnitService
	attributor     *spatialpkg.PMTilesAttributor
	keepProjects   bool
	keepWorking    bool
	keepAttributor bool

	userLog        *lifecyclepkg.UserLogService
	context        *ContextService
	plotEntry      *PlotEntryService
	datasheet      *DatasheetService
	classification *ClassificationService
	validation     *ValidationService
	importExport   *ImportExportService
	vegReport      *VegetationReportService
	envReport      *EnvironmentReportService
	spatial        *SpatialService
	pictures       *PictureService
	help           *HelpService
}

func (b *runtimeBundle) closeResources(logWarnings bool) {
	if b == nil {
		return
	}
	if b.working != nil && !b.keepWorking {
		if err := b.working.Close(); err != nil && logWarnings {
			log.Printf("Warning: failed to close WorkingUnitService: %v", err)
		}
	}
	if b.projects != nil && !b.keepProjects {
		if err := b.projects.CloseSQLiteContext(); err != nil && logWarnings {
			log.Printf("Warning: failed to close project context: %v", err)
		}
	}
	if b.attributor != nil && !b.keepAttributor {
		if err := b.attributor.Close(); err != nil && logWarnings {
			log.Printf("Warning: failed to close PMTilesAttributor: %v", err)
		}
	}
}

type runtimeShutdownTracker struct {
	mu        sync.Mutex
	current   *runtimeBundle
	extraDirs []string
}

func newRuntimeShutdownTracker(initial *runtimeBundle, extraDirs []string) *runtimeShutdownTracker {
	return &runtimeShutdownTracker{
		current:   initial,
		extraDirs: append([]string(nil), extraDirs...),
	}
}

func (t *runtimeShutdownTracker) acquire() (*runtimeBundle, func()) {
	if t == nil {
		return nil, noopRelease
	}
	t.mu.Lock()
	b := t.current
	if b == nil || b.retired {
		t.mu.Unlock()
		return nil, noopRelease
	}
	b.refs++
	t.mu.Unlock()
	var once sync.Once
	return b, func() {
		once.Do(func() {
			t.release(b)
		})
	}
}

func (t *runtimeShutdownTracker) release(b *runtimeBundle) {
	if t == nil || b == nil {
		return
	}
	var toClose *runtimeBundle
	t.mu.Lock()
	if b.refs > 0 {
		b.refs--
	}
	if b.refs == 0 && b.retired && !b.closed {
		b.closed = true
		toClose = b
	}
	t.mu.Unlock()
	if toClose != nil {
		toClose.closeResources(false)
	}
}

func (t *runtimeShutdownTracker) publish(next *runtimeBundle, extraDirs []string) {
	if t == nil {
		return
	}
	var toClose *runtimeBundle
	t.mu.Lock()
	prev := t.current
	if prev != nil && prev != next {
		if next != nil {
			prev.keepProjects = prev.projects == next.projects
			prev.keepWorking = prev.working == next.working
			prev.keepAttributor = prev.attributor == next.attributor
		}
		prev.retired = true
		if prev.refs == 0 && !prev.closed {
			prev.closed = true
			toClose = prev
		}
	}
	t.current = next
	t.extraDirs = append([]string(nil), extraDirs...)
	t.mu.Unlock()
	if toClose != nil {
		toClose.closeResources(false)
	}
}

func (t *runtimeShutdownTracker) currentExtraDirs() []string {
	if t == nil {
		return nil
	}
	t.mu.Lock()
	defer t.mu.Unlock()
	return append([]string(nil), t.extraDirs...)
}

func (t *runtimeShutdownTracker) shutdown(refs *referenceCatalogBundle, cloud *cloudsyncpkg.Manager) {
	if t != nil {
		var toClose *runtimeBundle
		t.mu.Lock()
		curr := t.current
		t.current = nil
		if curr != nil {
			curr.retired = true
			if curr.refs == 0 && !curr.closed {
				curr.closed = true
				toClose = curr
			}
		}
		t.mu.Unlock()
		if toClose != nil {
			toClose.closeResources(true)
		}
	}
	refs.Close()
	if cloud != nil {
		cloud.Close()
	}
}

func newStartupServiceWithInitialActivation(dataDir, configDir string, activate func() (StartupState, error)) *lifecyclepkg.StartupService {
	svc := &lifecyclepkg.StartupService{
		DataDir:  dataDir,
		Activate: activate,
		State:    StartupState{ConfigPath: filepath.Join(configDir, "config.yml"), ReleaseChannel: vprocorepkg.ReleaseChannelStable},
	}
	if initialState, initErr := activate(); initErr != nil {
		log.Printf("Saved context remains unavailable (entering startup recovery): %v", initErr)
		recoveryState := StartupState{
			Ready:          false,
			Message:        initErr.Error(),
			ConfigPath:     filepath.Join(configDir, "config.yml"),
			ReleaseChannel: vprocorepkg.ReleaseChannelStable,
		}
		lifecyclepkg.PopulateRecoveryHints(&recoveryState)
		svc.SetState(recoveryState)
	} else {
		svc.SetState(initialState)
	}
	return svc
}

type LifecycleService struct {
	runtime    *runtimeShutdownTracker
	startup    *lifecyclepkg.StartupService
	close      *lifecyclepkg.CloseService
	userLog    *lifecyclepkg.UserLogService
	onShutdown func()
}

// ServiceShutdown implements application.ServiceShutdown so Wails v3 cleanly
// tears down tracked SQLite, PMTiles, and cloud-sync resources on exit.
func (s *LifecycleService) ServiceShutdown() error {
	if s != nil && s.onShutdown != nil {
		s.onShutdown()
	}
	return nil
}

func NewLifecycleService(startup *lifecyclepkg.StartupService, closeSvc *lifecyclepkg.CloseService, userLog *lifecyclepkg.UserLogService) *LifecycleService {
	return &LifecycleService{
		startup: startup,
		close:   closeSvc,
		userLog: userLog,
	}
}

func (s *LifecycleService) GetStartupState() StartupState {
	if s == nil || s.startup == nil {
		return lifecyclepkg.WithBuildMetadata(StartupState{ReleaseChannel: vprocorepkg.ReleaseChannelStable})
	}
	return s.startup.GetState()
}

func (s *LifecycleService) ChooseStartupDatabaseFile(ctx context.Context) (string, error) {
	if s == nil || s.startup == nil {
		return "", errors.New("startup service is unavailable")
	}
	return s.startup.ChooseDatabaseFile(ctx)
}

func (s *LifecycleService) ResetStartupToSample(ctx context.Context) (StartupState, error) {
	if s == nil || s.startup == nil {
		return StartupState{}, errors.New("startup service is unavailable")
	}
	return s.startup.ResetToSample(ctx)
}

func (s *LifecycleService) RecoverStartupWithPaths(ctx context.Context, request StartupRecoveryRequest) (StartupState, error) {
	if s == nil || s.startup == nil {
		return StartupState{}, errors.New("startup service is unavailable")
	}
	return s.startup.RecoverWithPaths(ctx, request)
}

func (s *LifecycleService) GetPendingCloseRequest() string {
	if s == nil || s.close == nil {
		return ""
	}
	return s.close.GetPendingCloseRequest()
}

func (s *LifecycleService) ConfirmClose(requestID string) error {
	if s == nil || s.close == nil {
		return errors.New("close service is unavailable")
	}
	return s.close.ConfirmClose(requestID)
}

func (s *LifecycleService) CancelClose(requestID string) error {
	if s == nil || s.close == nil {
		return errors.New("close service is unavailable")
	}
	return s.close.CancelClose(requestID)
}

func (s *LifecycleService) GetUserLogReview(ctx context.Context, contextID string, mode, offset, limit int) (UserLogReview, error) {
	if s == nil {
		return UserLogReview{}, errors.New("user log service is unavailable")
	}
	userLog := s.userLog
	if s.runtime != nil {
		snap, release := s.runtime.acquire()
		defer release()
		if snap != nil {
			userLog = snap.userLog
		}
	}
	if userLog == nil {
		return UserLogReview{}, errors.New("user log service is unavailable")
	}
	return userLog.GetReview(ctx, contextID, mode, offset, limit)
}
