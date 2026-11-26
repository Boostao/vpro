package vprocore

import (
	"context"
	"errors"
	"fmt"
	"runtime"
	"strings"
	"sync"
	"weak"
)

const (
	AuthRoleViewer            = "viewer"
	AuthRoleContributor       = "contributor"
	AuthRoleRegionalEcologist = "regional_ecologist"
	AuthRoleCustodian         = "custodian"
)

var (
	// ErrEditingLockedSignInRequired is returned when a mutation is attempted while auth edit lock
	// enforcement is active and no authenticated session is present.
	ErrEditingLockedSignInRequired = errors.New("data editing is locked: sign in with your BC Government IDIR or BCeID account to unlock editing")

	// ErrBECMasterPermissionRequired is returned when an authenticated user lacks sufficient role
	// permissions to edit the active project (e.g., Viewer role or non-Custodian editing BECMaster).
	ErrBECMasterPermissionRequired = errors.New("permission required: your role cannot edit BECMaster or protected data")
)

// EditLockState describes the current data-editing lock status for the desktop UI and backend gates.
type EditLockState struct {
	Locked                bool   `json:"locked"`
	Reason                string `json:"reason"`
	SignedIn              bool   `json:"signedIn"`
	UserID                string `json:"userId"`
	DisplayName           string `json:"displayName"`
	Role                  string `json:"role"`
	IdentityProvider      string `json:"identityProvider"`
	CanEditCurrentProject bool   `json:"canEditCurrentProject"`
	IsBECMasterProject    bool   `json:"isBecMasterProject"`
	OIDCConfigured        bool   `json:"oidcConfigured"`
	DevFallbackAvailable  bool   `json:"devFallbackAvailable"`
}

// EditLockSnapshot is a secret-free identity snapshot supplied by the auth manager to vprocore.
type EditLockSnapshot struct {
	SignedIn             bool
	UserID               string
	DisplayName          string
	Role                 string
	IdentityProvider     string
	OIDCConfigured       bool
	DevFallbackAvailable bool
}

// EditLockProvider returns the current cached authentication snapshot without performing network I/O.
type EditLockProvider func() EditLockSnapshot

type editLockBinding struct {
	enforce  bool
	provider EditLockProvider
}

type editLockRegistry struct {
	mu      sync.RWMutex
	byPrefs map[weak.Pointer[DesktopConfig]]editLockBinding
	bySQL   map[weak.Pointer[SqliteContext]]editLockBinding
}

var contextEditLocks = &editLockRegistry{
	byPrefs: make(map[weak.Pointer[DesktopConfig]]editLockBinding),
	bySQL:   make(map[weak.Pointer[SqliteContext]]editLockBinding),
}

func (r *editLockRegistry) bindPrefs(prefs *DesktopConfig, b editLockBinding) {
	if prefs == nil {
		return
	}
	wp := weak.Make(prefs)
	r.mu.Lock()
	_, existed := r.byPrefs[wp]
	r.byPrefs[wp] = b
	r.mu.Unlock()
	if !existed {
		runtime.AddCleanup(prefs, func(key weak.Pointer[DesktopConfig]) {
			r.mu.Lock()
			delete(r.byPrefs, key)
			r.mu.Unlock()
		}, wp)
	}
}

func (r *editLockRegistry) bindSQLite(sqlCtx *SqliteContext, b editLockBinding) {
	if sqlCtx == nil {
		return
	}
	wp := weak.Make(sqlCtx)
	r.mu.Lock()
	_, existed := r.bySQL[wp]
	r.bySQL[wp] = b
	r.mu.Unlock()
	if !existed {
		runtime.AddCleanup(sqlCtx, func(key weak.Pointer[SqliteContext]) {
			r.mu.Lock()
			delete(r.bySQL, key)
			r.mu.Unlock()
		}, wp)
	}
}

func (r *editLockRegistry) lookup(prefs *DesktopConfig, sqlCtx *SqliteContext) (editLockBinding, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	if prefs != nil {
		if b, ok := r.byPrefs[weak.Make(prefs)]; ok {
			return b, true
		}
	}
	if sqlCtx != nil {
		if b, ok := r.bySQL[weak.Make(sqlCtx)]; ok {
			return b, true
		}
	}
	return editLockBinding{}, false
}

// IsBECMasterProjectName reports whether projectName identifies a provincial BECMaster database.
func IsBECMasterProjectName(projectName string) bool {
	lower := strings.ToLower(strings.TrimSpace(projectName))
	if lower == "" {
		return false
	}
	return lower == "becmaster" ||
		strings.HasPrefix(lower, "becmaster_") ||
		strings.HasPrefix(lower, "becmaster-") ||
		strings.HasPrefix(lower, "becmaster ")
}

func normalizeAuthRole(raw string) string {
	s := strings.ToLower(strings.TrimSpace(raw))
	s = strings.NewReplacer("-", "_", " ", "_").Replace(s)
	switch s {
	case AuthRoleViewer, AuthRoleContributor, AuthRoleRegionalEcologist, AuthRoleCustodian:
		return s
	default:
		return ""
	}
}

// EvaluateEditLock computes the UI and enforcement EditLockState for projectName and auth snapshot.
func EvaluateEditLock(projectName string, snap EditLockSnapshot) EditLockState {
	isMaster := IsBECMasterProjectName(projectName)
	role := ""
	if snap.SignedIn {
		role = normalizeAuthRole(snap.Role)
		if role == "" {
			role = AuthRoleViewer
		}
	}

	state := EditLockState{
		SignedIn:             snap.SignedIn,
		UserID:               strings.TrimSpace(snap.UserID),
		DisplayName:          strings.TrimSpace(snap.DisplayName),
		Role:                 role,
		IdentityProvider:     strings.TrimSpace(snap.IdentityProvider),
		IsBECMasterProject:   isMaster,
		OIDCConfigured:       snap.OIDCConfigured,
		DevFallbackAvailable: snap.DevFallbackAvailable,
	}

	if !snap.SignedIn {
		state.Locked = true
		state.CanEditCurrentProject = false
		state.Reason = "Sign in with your BC Government IDIR or BCeID account to unlock data editing."
		return state
	}

	switch role {
	case AuthRoleCustodian:
		state.Locked = false
		state.CanEditCurrentProject = true
		state.Reason = ""
	case AuthRoleRegionalEcologist, AuthRoleContributor:
		if isMaster {
			state.Locked = true
			state.CanEditCurrentProject = false
			state.Reason = "BECMaster is read-only for your role. Edit a local working project and submit changes through staging, or sign in as a Custodian."
		} else {
			state.Locked = false
			state.CanEditCurrentProject = true
			state.Reason = ""
		}
	default:
		state.Locked = true
		state.CanEditCurrentProject = false
		state.Reason = "Your account has read-only Viewer access. Contributor or higher accreditation is required to edit data."
	}

	return state
}

// SetEditLockProvider configures auth edit-lock enforcement directly on a PlotService.
func (s *PlotService) SetEditLockProvider(enforce bool, provider EditLockProvider) {
	if s == nil {
		return
	}
	s.Mu.Lock()
	s.EnforceAuthLock = enforce
	s.editLockProvider = provider
	projects := s.Projects
	s.Mu.Unlock()

	if projects != nil {
		projects.Mu.RLock()
		prefs := projects.Preferences
		sqlCtx := projects.Sqlite
		projects.Mu.RUnlock()
		binding := editLockBinding{enforce: enforce, provider: provider}
		contextEditLocks.bindPrefs(prefs, binding)
		contextEditLocks.bindSQLite(sqlCtx, binding)
	}
}

// SetContextEditLockProvider attaches auth edit-lock enforcement to a ContextService so all
// per-request scoped PlotService snapshots created by WithContextPlotRequest inherit it.
func SetContextEditLockProvider(s *ContextService, enforce bool, provider EditLockProvider) {
	if s == nil {
		return
	}
	binding := editLockBinding{enforce: enforce, provider: provider}
	if s.Plots != nil {
		s.Plots.Mu.Lock()
		s.Plots.EnforceAuthLock = enforce
		s.Plots.editLockProvider = provider
		s.Plots.Mu.Unlock()
	}
	if s.Projects != nil {
		s.Projects.Mu.RLock()
		prefs := s.Projects.Preferences
		sqlCtx := s.Projects.Sqlite
		s.Projects.Mu.RUnlock()
		contextEditLocks.bindPrefs(prefs, binding)
		contextEditLocks.bindSQLite(sqlCtx, binding)
	}
}

func (s *PlotService) resolveEditLockPolicy() (bool, EditLockProvider) {
	if s == nil {
		return false, nil
	}
	s.Mu.RLock()
	enforced := s.EnforceAuthLock
	provider := s.editLockProvider
	scoped := s.ContextScoped
	projects := s.Projects
	s.Mu.RUnlock()

	if projects != nil && (scoped || (!enforced && provider == nil)) {
		projects.Mu.RLock()
		prefs := projects.Preferences
		sqlCtx := projects.Sqlite
		projects.Mu.RUnlock()
		if b, ok := contextEditLocks.lookup(prefs, sqlCtx); ok {
			return b.enforce, b.provider
		}
	}
	return enforced, provider
}

func (s *PlotService) activeProjectName() string {
	if s == nil || s.Projects == nil {
		return ""
	}
	s.Projects.Mu.RLock()
	sqlCtx := s.Projects.Sqlite
	active := s.Projects.Active
	s.Projects.Mu.RUnlock()

	if sqlCtx != nil {
		sqlCtx.mu.Lock()
		proj := sqlCtx.Selection.Project
		sqlCtx.mu.Unlock()
		if strings.TrimSpace(proj) != "" {
			return proj
		}
	}
	return active
}

// EditLockStatus returns the evaluated EditLockState for the active project on this PlotService.
func (s *PlotService) EditLockStatus() EditLockState {
	_, provider := s.resolveEditLockPolicy()
	var snap EditLockSnapshot
	if provider != nil {
		snap = provider()
	}
	return EvaluateEditLock(s.activeProjectName(), snap)
}

// CheckEditLock enforces the default data edit lock when EnforceAuthLock is active.
// Direct PlotService unit tests with EnforceAuthLock=false remain unaffected.
func (s *PlotService) CheckEditLock() error {
	enforced, provider := s.resolveEditLockPolicy()
	if !enforced {
		return nil
	}
	var snap EditLockSnapshot
	if provider != nil {
		snap = provider()
	}
	state := EvaluateEditLock(s.activeProjectName(), snap)
	if !state.Locked && state.CanEditCurrentProject {
		return nil
	}
	if !state.SignedIn {
		return ErrEditingLockedSignInRequired
	}
	return fmt.Errorf("%w: %s", ErrBECMasterPermissionRequired, state.Reason)
}

// GetContextEditLockStatus evaluates EditLockState for a ContextService, validating contextID when provided.
func GetContextEditLockStatus(s *ContextService, ctx context.Context, contextID string) (EditLockState, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return EditLockState{}, err
	}
	if s == nil || s.Plots == nil {
		return EvaluateEditLock("", EditLockSnapshot{}), nil
	}
	if strings.TrimSpace(contextID) != "" {
		return WithContextPlotRequest(ctx, s, contextID, func(plots *PlotService) (EditLockState, error) {
			return plots.EditLockStatus(), nil
		})
	}
	return s.Plots.EditLockStatus(), nil
}
