package main

import (
	"context"
	"errors"
	"os"
	"strings"
	"sync"

	authpkg "github.com/boostao/vpro/app/internal/auth"
	lifecyclepkg "github.com/boostao/vpro/app/internal/lifecycle"
	sqlutilpkg "github.com/boostao/vpro/app/internal/sqlutil"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

type contextAuthHolder struct {
	manager *authpkg.Manager
}

var (
	fallbackAuthMu       sync.Mutex
	fallbackAuthManagers = make(map[string]*authpkg.Manager)
)

func editLockSnapshotFromSummary(summary authpkg.SessionSummary) vprocorepkg.EditLockSnapshot {
	return vprocorepkg.EditLockSnapshot{
		SignedIn:             summary.SignedIn,
		UserID:               summary.UserID,
		DisplayName:          summary.DisplayName,
		Role:                 summary.Role,
		IdentityProvider:     summary.IdentityProvider,
		OIDCConfigured:       summary.OIDCConfigured,
		DevFallbackAvailable: summary.DevFallbackAvailable,
	}
}

func newDesktopAuthManager(configDir string) *authpkg.Manager {
	info := lifecyclepkg.CurrentBuildInfo()
	return authpkg.NewManager(
		configDir,
		os.LookupEnv,
		authpkg.WithAppVersion(info.AppVersion),
		authpkg.WithDevMode(info.BuildMode == lifecyclepkg.BuildModeDev),
	)
}

func (s *ContextService) authManager() (*authpkg.Manager, *vprocorepkg.ContextService, error) {
	if s == nil {
		return nil, nil, errors.New("project context is unavailable")
	}
	if s.core != nil {
		core := s.core
		holder := vprocorepkg.ContextState(core, func() *contextAuthHolder {
			cfgDir := ""
			if core.Projects != nil {
				cfgDir = core.Projects.Config
			}
			mgr := newDesktopAuthManager(cfgDir)
			vprocorepkg.SetContextEditLockProvider(core, true, func() vprocorepkg.EditLockSnapshot {
				return editLockSnapshotFromSummary(mgr.CachedSessionSummary())
			})
			return &contextAuthHolder{manager: mgr}
		})
		return holder.manager, core, nil
	}

	cfgDir, err := sqlutilpkg.UserConfigDir()
	if err != nil {
		return nil, nil, err
	}
	fallbackAuthMu.Lock()
	defer fallbackAuthMu.Unlock()
	mgr, ok := fallbackAuthManagers[cfgDir]
	if !ok {
		mgr = newDesktopAuthManager(cfgDir)
		fallbackAuthManagers[cfgDir] = mgr
	}
	return mgr, nil, nil
}

func syncAuthActorToPlots(core *vprocorepkg.ContextService, summary authpkg.SessionSummary) {
	if core == nil || core.Plots == nil || !summary.SignedIn {
		return
	}
	actor := strings.TrimSpace(summary.DisplayName)
	if actor == "" {
		actor = strings.TrimSpace(summary.UserID)
	}
	if actor == "" {
		return
	}
	core.Plots.Mu.Lock()
	core.Plots.CurrentUser = actor
	core.Plots.Mu.Unlock()
}

// GetAuthSession returns the current cached/refreshed BC Gov OIDC (or dev evaluation) session summary.
func (s *ContextService) GetAuthSession(ctx context.Context) (authpkg.SessionSummary, error) {
	if err := requireContextArg(ctx); err != nil {
		return authpkg.SessionSummary{}, err
	}
	s, release := s.acquire()
	defer release()
	mgr, core, err := s.authManager()
	if err != nil {
		return authpkg.SessionSummary{}, err
	}
	summary, err := mgr.GetSession(ctx)
	if err != nil {
		return authpkg.SessionSummary{}, err
	}
	syncAuthActorToPlots(core, summary)
	info := lifecyclepkg.CurrentBuildInfo()
	_, _ = mgr.EnsureMachineEnrollment(ctx, info.AppVersion)
	return summary, nil
}

// GetEditLockStatus reports whether data editing is locked for the active project and why.
func (s *ContextService) GetEditLockStatus(ctx context.Context, contextID string) (vprocorepkg.EditLockState, error) {
	if err := requireContextArg(ctx); err != nil {
		return vprocorepkg.EditLockState{}, err
	}
	s, release := s.acquire()
	defer release()
	mgr, core, err := s.authManager()
	if err != nil {
		return vprocorepkg.EditLockState{}, err
	}
	if core == nil {
		return vprocorepkg.EvaluateEditLock("", editLockSnapshotFromSummary(mgr.CachedSessionSummary())), nil
	}
	return vprocorepkg.GetContextEditLockStatus(core, ctx, contextID)
}

// BeginOIDCSignIn initiates the BC Gov OIDC Authorization Code + PKCE browser flow on 127.0.0.1:0.
func (s *ContextService) BeginOIDCSignIn(ctx context.Context, providerHint string) (authpkg.SignInResult, error) {
	if err := requireContextArg(ctx); err != nil {
		return authpkg.SignInResult{}, err
	}
	s, release := s.acquire()
	defer release()
	mgr, core, err := s.authManager()
	if err != nil {
		return authpkg.SignInResult{}, err
	}
	res, err := mgr.BeginOIDCSignIn(ctx, providerHint)
	if err != nil {
		return res, err
	}
	if res.Completed && res.Session.SignedIn {
		syncAuthActorToPlots(core, res.Session)
		info := lifecyclepkg.CurrentBuildInfo()
		_, _ = mgr.EnsureMachineEnrollment(ctx, info.AppVersion)
	}
	return res, nil
}

// CompleteDevEvaluationSignIn signs in using a local evaluation identity (strictly gated to dev builds without OIDC configured).
func (s *ContextService) CompleteDevEvaluationSignIn(ctx context.Context, userID, displayName, role string) (authpkg.SessionSummary, error) {
	if err := requireContextArg(ctx); err != nil {
		return authpkg.SessionSummary{}, err
	}
	s, release := s.acquire()
	defer release()
	mgr, core, err := s.authManager()
	if err != nil {
		return authpkg.SessionSummary{}, err
	}
	summary, err := mgr.CompleteDevEvaluationSignIn(ctx, userID, displayName, role)
	if err != nil {
		return authpkg.SessionSummary{}, err
	}
	syncAuthActorToPlots(core, summary)
	return summary, nil
}

// SignOut clears persisted machine tokens and re-locks data editing until the user signs in again.
func (s *ContextService) SignOut(ctx context.Context) (authpkg.SessionSummary, error) {
	if err := requireContextArg(ctx); err != nil {
		return authpkg.SessionSummary{}, err
	}
	s, release := s.acquire()
	defer release()
	mgr, core, err := s.authManager()
	if err != nil {
		return authpkg.SessionSummary{}, err
	}
	summary, err := mgr.SignOut(ctx)
	if err != nil {
		return authpkg.SessionSummary{}, err
	}
	if core != nil && core.Plots != nil {
		core.Plots.Mu.Lock()
		core.Plots.CurrentUser = ""
		core.Plots.Mu.Unlock()
	}
	return summary, nil
}

// RecordAppActivity records a non-blocking, offline-tolerant app download/enrollment or dataset upload event.
func (s *ContextService) RecordAppActivity(ctx context.Context, eventKind, datasetName string, plotCount int) (authpkg.ActivityRecordResult, error) {
	if err := requireContextArg(ctx); err != nil {
		return authpkg.ActivityRecordResult{}, err
	}
	s, release := s.acquire()
	defer release()
	mgr, _, err := s.authManager()
	if err != nil {
		return authpkg.ActivityRecordResult{}, err
	}
	return mgr.RecordActivity(ctx, eventKind, datasetName, plotCount)
}
