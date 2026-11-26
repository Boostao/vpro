package auth

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/sha512"
	"crypto/subtle"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"hash"
	"html"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"time"
)

const (
	// DefaultBCGovOIDCIssuer is the BC Government Common Hosted Single Sign-on (CSS) standard realm.
	DefaultBCGovOIDCIssuer = "https://loginproxy.gov.bc.ca/auth/realms/standard"
	DefaultOIDCScopes      = "openid profile email"

	RoleViewer            = "viewer"
	RoleContributor       = "contributor"
	RoleRegionalEcologist = "regional_ecologist"
	RoleCustodian         = "custodian"

	defaultOIDCSignInTimeout = 3 * time.Minute
	defaultHTTPTimeout       = 15 * time.Second
	silentRefreshTimeout     = 5 * time.Second
	refreshSkewWindow        = 5 * time.Minute
	jwtClockSkew             = 60 * time.Second
	maxOIDCResponseBytes     = 1 << 20 // 1 MiB
)

var (
	// ErrOIDCNotConfigured is returned when real OIDC sign-in is requested without VPRO_OIDC_CLIENT_ID.
	ErrOIDCNotConfigured = errors.New("BC Government OIDC sign-in is not configured (set VPRO_OIDC_CLIENT_ID)")
	// ErrDevFallbackDisabled is returned when dev evaluation sign-in is attempted in production builds or when OIDC is configured.
	ErrDevFallbackDisabled = errors.New("development evaluation sign-in is disabled in this build")
	// ErrTokenRevoked is returned when the OIDC provider explicitly rejects a refresh token with invalid_grant.
	ErrTokenRevoked = errors.New("saved sign-in session was revoked by the identity provider")

	idpHintPattern = regexp.MustCompile(`^[a-zA-Z0-9_-]{1,32}$`)
)

// EnvLookup resolves an environment variable.
type EnvLookup func(key string) (string, bool)

// BrowserOpener opens an authorization URL in the user's system browser.
type BrowserOpener func(rawURL string) error

// OIDCConfig holds resolved runtime OIDC configuration.
type OIDCConfig struct {
	Issuer       string
	ClientID     string
	Scopes       string
	RoleClaimKey string
}

// SignInResult is returned by BeginOIDCSignIn with both the auth URL and resulting session state.
type SignInResult struct {
	AuthURL       string         `json:"authUrl"`
	Completed     bool           `json:"completed"`
	BrowserOpened bool           `json:"browserOpened"`
	Warning       string         `json:"warning,omitempty"`
	Session       SessionSummary `json:"session"`
}

// Manager coordinates OIDC sign-in, offline-capable session caching, silent refresh, and activity telemetry.
type Manager struct {
	mu              sync.Mutex
	configDir       string
	envLookup       EnvLookup
	httpClient      *http.Client
	openBrowser     BrowserOpener
	nowFunc         func() time.Time
	appVersion      string
	devModeOverride *bool

	loaded      bool
	offlineMode bool
	session     StoredSession

	discoveryCache map[string]oidcDiscoveryDoc
	jwksCache      map[string]jwkSet

	telemetryMu sync.Mutex
	flushMu     sync.Mutex
	pgSink      PGActivitySink
}

// Option customizes a Manager instance (primarily for tests and desktop host wiring).
type Option func(*Manager)

func WithHTTPClient(client *http.Client) Option {
	return func(m *Manager) {
		if client != nil {
			m.httpClient = client
		}
	}
}

func WithBrowserOpener(opener BrowserOpener) Option {
	return func(m *Manager) {
		m.openBrowser = opener
	}
}

func WithClock(now func() time.Time) Option {
	return func(m *Manager) {
		if now != nil {
			m.nowFunc = now
		}
	}
}

func WithAppVersion(version string) Option {
	return func(m *Manager) {
		m.appVersion = strings.TrimSpace(version)
	}
}

func WithDevMode(enabled bool) Option {
	return func(m *Manager) {
		v := enabled
		m.devModeOverride = &v
	}
}

func WithPGActivitySink(sink PGActivitySink) Option {
	return func(m *Manager) {
		m.pgSink = sink
	}
}

// NewManager creates an auth Manager storing state under configDir.
func NewManager(configDir string, envLookup EnvLookup, opts ...Option) *Manager {
	if envLookup == nil {
		envLookup = os.LookupEnv
	}
	m := &Manager{
		configDir: configDir,
		envLookup: envLookup,
		httpClient: &http.Client{
			Timeout: defaultHTTPTimeout,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if len(via) >= 5 {
					return errors.New("too many redirects")
				}
				return requireHTTPSOrLoopback(req.URL.String())
			},
		},
		openBrowser:    defaultOpenBrowser,
		nowFunc:        time.Now,
		appVersion:     "2.0.0-dev",
		discoveryCache: make(map[string]oidcDiscoveryDoc),
		jwksCache:      make(map[string]jwkSet),
	}
	for _, opt := range opts {
		if opt != nil {
			opt(m)
		}
	}
	return m
}

func (m *Manager) now() time.Time {
	if m != nil && m.nowFunc != nil {
		return m.nowFunc().UTC()
	}
	return time.Now().UTC()
}

func (m *Manager) env(key string) string {
	if m == nil || m.envLookup == nil {
		return ""
	}
	val, ok := m.envLookup(key)
	if !ok {
		return ""
	}
	return strings.TrimSpace(val)
}

// ResolveOIDCConfig resolves OIDC settings from environment variables with BC Gov CSS defaults.
func (m *Manager) ResolveOIDCConfig() OIDCConfig {
	issuer := strings.TrimRight(m.env("VPRO_OIDC_ISSUER"), "/")
	if issuer == "" {
		issuer = DefaultBCGovOIDCIssuer
	}
	scopes := m.env("VPRO_OIDC_SCOPES")
	if scopes == "" {
		scopes = DefaultOIDCScopes
	}
	return OIDCConfig{
		Issuer:       issuer,
		ClientID:     m.env("VPRO_OIDC_CLIENT_ID"),
		Scopes:       scopes,
		RoleClaimKey: m.env("VPRO_OIDC_ROLE_CLAIM"),
	}
}

func (m *Manager) oidcConfiguredLocked() bool {
	return m.ResolveOIDCConfig().ClientID != ""
}

// OIDCConfigured reports whether an OIDC client ID has been configured.
func (m *Manager) OIDCConfigured() bool {
	if m == nil {
		return false
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.oidcConfiguredLocked()
}

func (m *Manager) devFallbackAvailableLocked() bool {
	// Production-tagged binaries NEVER permit dev evaluation fallback.
	if compiledProductionBuild {
		return false
	}
	// Whenever real OIDC is configured, disable dev fallback so real auth cannot be bypassed.
	if m.oidcConfiguredLocked() {
		return false
	}
	if m.devModeOverride != nil {
		return *m.devModeOverride
	}
	switch strings.ToLower(m.env("VPRO_BUILD_MODE")) {
	case "release", "prod", "production", "alpha", "preview", "rc", "beta":
		return false
	}
	return true
}

// DevFallbackAvailable reports whether dev-only evaluation sign-in is permitted.
func (m *Manager) DevFallbackAvailable() bool {
	if m == nil {
		return false
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.devFallbackAvailableLocked()
}

// NormalizeRole canonicalizes a VPro role string or returns "" if unrecognized.
func NormalizeRole(raw string) string {
	s := strings.ToLower(strings.TrimSpace(raw))
	s = strings.NewReplacer("-", "_", " ", "_").Replace(s)
	switch s {
	case "viewer", "vpro_viewer", "readonly", "read_only", "public":
		return RoleViewer
	case "contributor", "vpro_contributor", "bec_contributor", "field_contributor", "editor", "vpro_editor":
		return RoleContributor
	case "regional_ecologist", "vpro_regional_ecologist", "bec_regional_ecologist", "regional_bec_ecologist", "ecologist":
		return RoleRegionalEcologist
	case "custodian", "vpro_custodian", "becmaster_custodian", "bec_custodian", "admin", "vpro_admin":
		return RoleCustodian
	default:
		return ""
	}
}

// IsValidRole returns true for the 4 canonical VPro role identifiers.
func IsValidRole(role string) bool {
	switch role {
	case RoleViewer, RoleContributor, RoleRegionalEcologist, RoleCustodian:
		return true
	default:
		return false
	}
}

// RoleRank returns privilege ordering (higher means broader edit permissions).
func RoleRank(role string) int {
	switch role {
	case RoleViewer:
		return 1
	case RoleContributor:
		return 2
	case RoleRegionalEcologist:
		return 3
	case RoleCustodian:
		return 4
	default:
		return 0
	}
}

// RoleCanEditWorkingProject reports whether role can edit local/working projects.
func RoleCanEditWorkingProject(role string) bool {
	return RoleRank(role) >= RoleRank(RoleContributor)
}

// RoleCanEditBECMaster reports whether role can directly edit BECMaster or protected master fields.
func RoleCanEditBECMaster(role string) bool {
	return role == RoleCustodian
}

// MapBCGovRoles maps raw BC Gov CSS / Keycloak role strings to the highest matching VPro role.
// Unknown or empty role lists fail safe to RoleViewer.
func MapBCGovRoles(rawRoles []string) string {
	best := RoleViewer
	bestRank := RoleRank(best)
	for _, r := range rawRoles {
		mapped := NormalizeRole(r)
		if rank := RoleRank(mapped); rank > bestRank {
			best = mapped
			bestRank = rank
		}
	}
	return best
}

// CachedSessionSummary returns the current cached session without performing any network calls.
// Safe for synchronous edit-lock checks.
func (m *Manager) CachedSessionSummary() SessionSummary {
	if m == nil {
		return SessionSummary{RawRoles: []string{}}
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	sess, err := m.loadStoredSessionLocked()
	if err != nil {
		return SessionSummary{
			RawRoles:             []string{},
			OIDCConfigured:       m.oidcConfiguredLocked(),
			DevFallbackAvailable: m.devFallbackAvailableLocked(),
		}
	}
	return m.buildSummaryLocked(sess, m.offlineMode)
}

// GetSession returns the current session, restoring persisted machine identity from disk
// and attempting a non-fatal silent token refresh if online and near/past token expiry.
func (m *Manager) GetSession(ctx context.Context) (SessionSummary, error) {
	if m == nil {
		return SessionSummary{RawRoles: []string{}}, errors.New("auth manager is unavailable")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return SessionSummary{}, err
	}

	m.mu.Lock()
	sess, err := m.loadStoredSessionLocked()
	if err != nil {
		m.mu.Unlock()
		return SessionSummary{}, err
	}
	needsRefresh := m.shouldSilentRefreshLocked(sess)
	cfg := m.ResolveOIDCConfig()
	m.mu.Unlock()

	if needsRefresh {
		refCtx, cancel := context.WithTimeout(ctx, silentRefreshTimeout)
		defer cancel()
		if refErr := m.trySilentRefresh(refCtx, cfg); refErr != nil {
			if errors.Is(refErr, ErrTokenRevoked) {
				// Explicit revocation by the IdP clears cached credentials immediately.
				m.mu.Lock()
				cleared := StoredSession{
					Version:   authSessionVersion,
					MachineID: sess.MachineID,
				}
				_ = m.persistStoredSessionLocked(cleared)
				m.offlineMode = false
				summary := m.buildSummaryLocked(cleared, false)
				m.mu.Unlock()
				return summary, nil
			}
			// Network/offline error: keep cached verified identity and report offline mode.
			m.mu.Lock()
			m.offlineMode = true
			summary := m.buildSummaryLocked(m.session, true)
			m.mu.Unlock()
			return summary, nil
		}
	}

	m.mu.Lock()
	summary := m.buildSummaryLocked(m.session, m.offlineMode)
	m.mu.Unlock()
	return summary, nil
}

func (m *Manager) shouldSilentRefreshLocked(sess StoredSession) bool {
	if !sess.SignedIn || sess.IsDevEvaluation || strings.TrimSpace(sess.RefreshToken) == "" {
		return false
	}
	if !m.oidcConfiguredLocked() {
		return false
	}
	if strings.TrimSpace(sess.TokenExpiresAt) == "" {
		return true
	}
	exp, err := time.Parse(time.RFC3339, sess.TokenExpiresAt)
	if err != nil {
		return true
	}
	return !m.now().Add(refreshSkewWindow).Before(exp)
}

// CompleteDevEvaluationSignIn creates a local evaluation session when running in dev mode
// without a configured OIDC client ID. Production builds and OIDC-configured environments reject it.
func (m *Manager) CompleteDevEvaluationSignIn(ctx context.Context, userID, displayName, role string) (SessionSummary, error) {
	if m == nil {
		return SessionSummary{}, errors.New("auth manager is unavailable")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return SessionSummary{}, err
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	if !m.devFallbackAvailableLocked() {
		return SessionSummary{}, ErrDevFallbackDisabled
	}

	cleanUser := strings.TrimSpace(userID)
	if cleanUser == "" {
		return SessionSummary{}, errors.New("user ID is required for development evaluation sign-in")
	}
	if len(cleanUser) > 128 {
		return SessionSummary{}, errors.New("user ID exceeds maximum length")
	}
	cleanDisplay := strings.TrimSpace(displayName)
	if cleanDisplay == "" {
		cleanDisplay = cleanUser
	}
	if len(cleanDisplay) > 160 {
		return SessionSummary{}, errors.New("display name exceeds maximum length")
	}
	cleanRole := NormalizeRole(role)
	if cleanRole == "" {
		return SessionSummary{}, fmt.Errorf("invalid role %q (expected viewer, contributor, regional_ecologist, or custodian)", role)
	}

	existing, err := m.loadStoredSessionLocked()
	if err != nil {
		return SessionSummary{}, err
	}

	nowStr := m.now().Format(time.RFC3339)
	next := StoredSession{
		Version:          authSessionVersion,
		MachineID:        existing.MachineID,
		SignedIn:         true,
		Issuer:           "vpro://dev-evaluation",
		Subject:          "dev:" + cleanUser,
		UserID:           cleanUser,
		DisplayName:      cleanDisplay,
		Role:             cleanRole,
		RawRoles:         []string{cleanRole},
		IdentityProvider: "dev_evaluation",
		IsDevEvaluation:  true,
		SignedInAt:       nowStr,
		VerifiedAt:       nowStr,
	}
	if err := m.persistStoredSessionLocked(next); err != nil {
		return SessionSummary{}, err
	}
	m.offlineMode = false
	return m.buildSummaryLocked(next, false), nil
}

// SignOut clears persisted tokens and signed-in identity while keeping the machine ID.
func (m *Manager) SignOut(ctx context.Context) (SessionSummary, error) {
	if m == nil {
		return SessionSummary{}, errors.New("auth manager is unavailable")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return SessionSummary{}, err
	}

	m.mu.Lock()
	defer m.mu.Unlock()

	existing, err := m.loadStoredSessionLocked()
	if err != nil {
		return SessionSummary{}, err
	}
	cleared := StoredSession{
		Version:   authSessionVersion,
		MachineID: existing.MachineID,
	}
	if err := m.persistStoredSessionLocked(cleared); err != nil {
		return SessionSummary{}, err
	}
	m.offlineMode = false
	return m.buildSummaryLocked(cleared, false), nil
}

// BeginOIDCSignIn executes an RFC 7636 Authorization Code + PKCE sign-in flow against
// the configured BC Gov CSS (or override) OIDC issuer using a 127.0.0.1:0 loopback listener.
func (m *Manager) BeginOIDCSignIn(ctx context.Context, providerHint string) (SignInResult, error) {
	if m == nil {
		return SignInResult{}, errors.New("auth manager is unavailable")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return SignInResult{}, err
	}

	cfg := m.ResolveOIDCConfig()
	if cfg.ClientID == "" {
		return SignInResult{}, ErrOIDCNotConfigured
	}
	if err := requireHTTPSOrLoopback(cfg.Issuer); err != nil {
		return SignInResult{}, err
	}

	hint := strings.TrimSpace(providerHint)
	if hint != "" && !idpHintPattern.MatchString(hint) {
		return SignInResult{}, errors.New("invalid identity provider hint")
	}

	// Ensure bounded wait even if caller passed a context without a deadline.
	flowCtx := ctx
	var cancel context.CancelFunc
	if _, hasDeadline := ctx.Deadline(); !hasDeadline {
		flowCtx, cancel = context.WithTimeout(ctx, defaultOIDCSignInTimeout)
		defer cancel()
	}

	doc, err := m.fetchDiscovery(flowCtx, cfg.Issuer)
	if err != nil {
		return SignInResult{}, err
	}

	verifier, challenge, err := generatePKCEPair()
	if err != nil {
		return SignInResult{}, fmt.Errorf("generate PKCE challenge: %w", err)
	}
	state, err := randomURLToken(32)
	if err != nil {
		return SignInResult{}, fmt.Errorf("generate OIDC state: %w", err)
	}
	nonce, err := randomURLToken(32)
	if err != nil {
		return SignInResult{}, fmt.Errorf("generate OIDC nonce: %w", err)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return SignInResult{}, fmt.Errorf("start loopback OIDC callback listener: %w", err)
	}
	defer ln.Close()

	redirectURI := fmt.Sprintf("http://%s/callback", ln.Addr().String())
	authURL, err := buildAuthorizationURL(doc.AuthorizationEndpoint, cfg, redirectURI, state, nonce, challenge, hint)
	if err != nil {
		return SignInResult{}, err
	}

	type callbackOutcome struct {
		code string
		err  error
	}
	outcomeCh := make(chan callbackOutcome, 1)
	var deliverOnce sync.Once
	deliver := func(res callbackOutcome) {
		deliverOnce.Do(func() {
			outcomeCh <- res
		})
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		q := r.URL.Query()
		gotState := q.Get("state")
		if subtle.ConstantTimeCompare([]byte(gotState), []byte(state)) != 1 {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(renderCallbackHTML(false, "Sign-in could not be verified (state mismatch). Please try again from VPro.")))
			deliver(callbackOutcome{err: errors.New("OIDC callback state mismatch")})
			return
		}
		if errCode := strings.TrimSpace(q.Get("error")); errCode != "" {
			errDesc := strings.TrimSpace(q.Get("error_description"))
			msg := "Sign-in was cancelled or denied by the identity provider."
			if errDesc != "" {
				msg = fmt.Sprintf("Sign-in failed (%s): %s", errCode, errDesc)
			}
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(renderCallbackHTML(false, msg)))
			deliver(callbackOutcome{err: wrapRedactedAuthError("OIDC provider error", fmt.Errorf("%s: %s", errCode, errDesc))})
			return
		}
		code := strings.TrimSpace(q.Get("code"))
		if code == "" {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(renderCallbackHTML(false, "No authorization code was returned. Please try again from VPro.")))
			deliver(callbackOutcome{err: errors.New("OIDC callback missing authorization code")})
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(renderCallbackHTML(true, "Sign-in complete. You can close this browser tab and return to VPro.")))
		deliver(callbackOutcome{code: code})
	})

	srv := &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		_ = srv.Serve(ln)
	}()
	defer func() {
		shutCtx, shutCancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer shutCancel()
		_ = srv.Shutdown(shutCtx)
	}()

	result := SignInResult{AuthURL: authURL}
	if m.openBrowser != nil {
		if openErr := m.openBrowser(authURL); openErr != nil {
			result.BrowserOpened = false
			result.Warning = "Could not open browser automatically; open the sign-in URL manually."
		} else {
			result.BrowserOpened = true
		}
	}

	var code string
	select {
	case out := <-outcomeCh:
		if out.err != nil {
			return result, out.err
		}
		code = out.code
	case <-flowCtx.Done():
		return result, fmt.Errorf("OIDC sign-in did not complete: %w", flowCtx.Err())
	}

	tokResp, err := m.exchangeAuthorizationCode(flowCtx, doc.TokenEndpoint, cfg, redirectURI, code, verifier)
	if err != nil {
		return result, err
	}

	verified, err := m.verifyAndExtractIdentity(flowCtx, doc, cfg, tokResp, nonce)
	if err != nil {
		return result, err
	}

	m.mu.Lock()
	existing, loadErr := m.loadStoredSessionLocked()
	if loadErr != nil {
		m.mu.Unlock()
		return result, loadErr
	}
	nowTime := m.now()
	nowStr := nowTime.Format(time.RFC3339)
	verified.Version = authSessionVersion
	verified.MachineID = existing.MachineID
	verified.SignedIn = true
	verified.SignedInAt = nowStr
	verified.VerifiedAt = nowStr
	verified.LastRefreshAt = nowStr
	if tokResp.ExpiresIn > 0 {
		verified.TokenExpiresAt = nowTime.Add(time.Duration(tokResp.ExpiresIn) * time.Second).Format(time.RFC3339)
	}
	verified.AccessToken = tokResp.AccessToken
	verified.RefreshToken = tokResp.RefreshToken
	verified.IDToken = tokResp.IDToken

	if err := m.persistStoredSessionLocked(verified); err != nil {
		m.mu.Unlock()
		return result, err
	}
	m.offlineMode = false
	summary := m.buildSummaryLocked(verified, false)
	m.mu.Unlock()

	result.Completed = true
	result.Session = summary
	return result, nil
}

func (m *Manager) trySilentRefresh(ctx context.Context, cfg OIDCConfig) error {
	m.mu.Lock()
	sess := m.session
	m.mu.Unlock()

	if strings.TrimSpace(sess.RefreshToken) == "" {
		return errors.New("no refresh token available")
	}
	issuer := sess.Issuer
	if issuer == "" {
		issuer = cfg.Issuer
	}
	if err := requireHTTPSOrLoopback(issuer); err != nil {
		return err
	}
	doc, err := m.fetchDiscovery(ctx, issuer)
	if err != nil {
		return err
	}

	form := url.Values{}
	form.Set("grant_type", "refresh_token")
	form.Set("client_id", cfg.ClientID)
	form.Set("refresh_token", sess.RefreshToken)

	tokResp, oauthErrCode, err := m.postTokenForm(ctx, doc.TokenEndpoint, form, sess.RefreshToken)
	if err != nil {
		if strings.EqualFold(oauthErrCode, "invalid_grant") {
			return ErrTokenRevoked
		}
		return err
	}

	m.mu.Lock()
	updated := m.session
	m.mu.Unlock()

	nowTime := m.now()
	nowStr := nowTime.Format(time.RFC3339)

	if strings.TrimSpace(tokResp.IDToken) != "" {
		verified, vErr := m.verifyAndExtractIdentity(ctx, doc, cfg, tokResp, "")
		if vErr != nil {
			return vErr
		}
		// Ensure subject matches the original authenticated user on refresh.
		if updated.Subject != "" && verified.Subject != updated.Subject {
			return errors.New("refreshed ID token subject mismatch")
		}
		updated.UserID = verified.UserID
		updated.DisplayName = verified.DisplayName
		updated.Email = verified.Email
		updated.Role = verified.Role
		updated.RawRoles = verified.RawRoles
		updated.IdentityProvider = verified.IdentityProvider
		updated.VerifiedAt = nowStr
		updated.IDToken = tokResp.IDToken
	} else {
		updated.VerifiedAt = nowStr
	}

	if tokResp.AccessToken != "" {
		updated.AccessToken = tokResp.AccessToken
	}
	if tokResp.RefreshToken != "" {
		updated.RefreshToken = tokResp.RefreshToken
	}
	if tokResp.ExpiresIn > 0 {
		updated.TokenExpiresAt = nowTime.Add(time.Duration(tokResp.ExpiresIn) * time.Second).Format(time.RFC3339)
	}
	updated.LastRefreshAt = nowStr

	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.persistStoredSessionLocked(updated); err != nil {
		return err
	}
	m.offlineMode = false
	return nil
}

type oidcDiscoveryDoc struct {
	Issuer                string `json:"issuer"`
	AuthorizationEndpoint string `json:"authorization_endpoint"`
	TokenEndpoint         string `json:"token_endpoint"`
	JWKSURI               string `json:"jwks_uri"`
	EndSessionEndpoint    string `json:"end_session_endpoint"`
}

func (m *Manager) fetchDiscovery(ctx context.Context, issuer string) (oidcDiscoveryDoc, error) {
	cleanIssuer := strings.TrimRight(strings.TrimSpace(issuer), "/")
	if err := requireHTTPSOrLoopback(cleanIssuer); err != nil {
		return oidcDiscoveryDoc{}, err
	}
	m.mu.Lock()
	if cached, ok := m.discoveryCache[cleanIssuer]; ok {
		m.mu.Unlock()
		return cached, nil
	}
	m.mu.Unlock()

	wellKnown := cleanIssuer + "/.well-known/openid-configuration"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, wellKnown, nil)
	if err != nil {
		return oidcDiscoveryDoc{}, err
	}
	req.Header.Set("Accept", "application/json")
	resp, err := m.httpClient.Do(req)
	if err != nil {
		return oidcDiscoveryDoc{}, wrapRedactedAuthError("fetch OIDC discovery metadata", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return oidcDiscoveryDoc{}, fmt.Errorf("OIDC discovery returned HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxOIDCResponseBytes))
	if err != nil {
		return oidcDiscoveryDoc{}, fmt.Errorf("read OIDC discovery metadata: %w", err)
	}
	var doc oidcDiscoveryDoc
	if err := json.Unmarshal(body, &doc); err != nil {
		return oidcDiscoveryDoc{}, fmt.Errorf("parse OIDC discovery metadata: %w", err)
	}
	if strings.TrimRight(doc.Issuer, "/") != cleanIssuer {
		return oidcDiscoveryDoc{}, fmt.Errorf("OIDC discovery issuer mismatch: got %q, want %q", doc.Issuer, cleanIssuer)
	}
	for _, ep := range []struct {
		name string
		val  string
	}{
		{"authorization_endpoint", doc.AuthorizationEndpoint},
		{"token_endpoint", doc.TokenEndpoint},
		{"jwks_uri", doc.JWKSURI},
	} {
		if strings.TrimSpace(ep.val) == "" {
			return oidcDiscoveryDoc{}, fmt.Errorf("OIDC discovery missing %s", ep.name)
		}
		if err := requireHTTPSOrLoopback(ep.val); err != nil {
			return oidcDiscoveryDoc{}, fmt.Errorf("OIDC discovery %s: %w", ep.name, err)
		}
	}

	m.mu.Lock()
	m.discoveryCache[cleanIssuer] = doc
	m.mu.Unlock()
	return doc, nil
}

type oidcTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	IDToken      string `json:"id_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int64  `json:"expires_in"`
	Error        string `json:"error"`
	ErrorDesc    string `json:"error_description"`
}

func (m *Manager) exchangeAuthorizationCode(ctx context.Context, tokenEndpoint string, cfg OIDCConfig, redirectURI, code, verifier string) (oidcTokenResponse, error) {
	form := url.Values{}
	form.Set("grant_type", "authorization_code")
	form.Set("client_id", cfg.ClientID)
	form.Set("code", code)
	form.Set("redirect_uri", redirectURI)
	form.Set("code_verifier", verifier)
	resp, _, err := m.postTokenForm(ctx, tokenEndpoint, form, code, verifier)
	return resp, err
}

func (m *Manager) postTokenForm(ctx context.Context, tokenEndpoint string, form url.Values, extraSecrets ...string) (oidcTokenResponse, string, error) {
	if err := requireHTTPSOrLoopback(tokenEndpoint); err != nil {
		return oidcTokenResponse{}, "", err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, tokenEndpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return oidcTokenResponse{}, "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	resp, err := m.httpClient.Do(req)
	if err != nil {
		return oidcTokenResponse{}, "", wrapRedactedAuthError("OIDC token request failed", err, extraSecrets...)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxOIDCResponseBytes))
	if err != nil {
		return oidcTokenResponse{}, "", fmt.Errorf("read OIDC token response: %w", err)
	}
	var tok oidcTokenResponse
	_ = json.Unmarshal(body, &tok)
	allSecrets := append([]string(nil), extraSecrets...)
	if tok.AccessToken != "" {
		allSecrets = append(allSecrets, tok.AccessToken)
	}
	if tok.RefreshToken != "" {
		allSecrets = append(allSecrets, tok.RefreshToken)
	}
	if tok.IDToken != "" {
		allSecrets = append(allSecrets, tok.IDToken)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		code := strings.TrimSpace(tok.Error)
		desc := RedactAuthSecrets(strings.TrimSpace(tok.ErrorDesc), allSecrets...)
		if code != "" {
			return oidcTokenResponse{}, code, fmt.Errorf("OIDC token endpoint rejected request (%s): %s", code, desc)
		}
		return oidcTokenResponse{}, "", fmt.Errorf("OIDC token endpoint returned HTTP %d", resp.StatusCode)
	}
	if strings.TrimSpace(tok.IDToken) == "" && strings.TrimSpace(tok.AccessToken) == "" {
		return oidcTokenResponse{}, "", errors.New("OIDC token response did not contain tokens")
	}
	return tok, "", nil
}

type jwkSet struct {
	Keys []jwkKey `json:"keys"`
}

type jwkKey struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
	Crv string `json:"crv"`
	X   string `json:"x"`
	Y   string `json:"y"`
}

func (m *Manager) fetchJWKS(ctx context.Context, jwksURI string, forceRefresh bool) (jwkSet, error) {
	if err := requireHTTPSOrLoopback(jwksURI); err != nil {
		return jwkSet{}, err
	}
	if !forceRefresh {
		m.mu.Lock()
		if cached, ok := m.jwksCache[jwksURI]; ok {
			m.mu.Unlock()
			return cached, nil
		}
		m.mu.Unlock()
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, jwksURI, nil)
	if err != nil {
		return jwkSet{}, err
	}
	req.Header.Set("Accept", "application/json")
	resp, err := m.httpClient.Do(req)
	if err != nil {
		return jwkSet{}, wrapRedactedAuthError("fetch JWKS keys", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return jwkSet{}, fmt.Errorf("JWKS endpoint returned HTTP %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxOIDCResponseBytes))
	if err != nil {
		return jwkSet{}, fmt.Errorf("read JWKS response: %w", err)
	}
	var set jwkSet
	if err := json.Unmarshal(body, &set); err != nil {
		return jwkSet{}, fmt.Errorf("parse JWKS response: %w", err)
	}
	m.mu.Lock()
	m.jwksCache[jwksURI] = set
	m.mu.Unlock()
	return set, nil
}

type jwtHeader struct {
	Alg string `json:"alg"`
	Kid string `json:"kid"`
	Typ string `json:"typ"`
}

func (m *Manager) verifyJWTWithJWKS(ctx context.Context, jwksURI, rawJWT string) (map[string]any, error) {
	parts := strings.Split(rawJWT, ".")
	if len(parts) != 3 {
		return nil, errors.New("invalid JWT compact serialization")
	}
	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, errors.New("invalid JWT header encoding")
	}
	var hdr jwtHeader
	if err := json.Unmarshal(headerBytes, &hdr); err != nil {
		return nil, errors.New("invalid JWT header JSON")
	}
	if !isAllowedJWSAlg(hdr.Alg) {
		return nil, fmt.Errorf("unsupported or disallowed JWT signature algorithm %q", hdr.Alg)
	}

	payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, errors.New("invalid JWT payload encoding")
	}
	sigBytes, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return nil, errors.New("invalid JWT signature encoding")
	}
	signingInput := []byte(parts[0] + "." + parts[1])

	set, err := m.fetchJWKS(ctx, jwksURI, false)
	if err != nil {
		return nil, err
	}
	key, ok := selectJWK(set, hdr.Kid, hdr.Alg)
	if !ok {
		// Retry once forcing JWKS refresh in case the IdP rotated signing keys.
		set, err = m.fetchJWKS(ctx, jwksURI, true)
		if err != nil {
			return nil, err
		}
		key, ok = selectJWK(set, hdr.Kid, hdr.Alg)
		if !ok {
			return nil, fmt.Errorf("no matching JWKS signing key found for kid %q and alg %q", hdr.Kid, hdr.Alg)
		}
	}

	if err := verifyJWSSignature(key, hdr.Alg, signingInput, sigBytes); err != nil {
		return nil, err
	}

	var claims map[string]any
	if err := json.Unmarshal(payloadBytes, &claims); err != nil {
		return nil, errors.New("invalid JWT claims JSON")
	}
	return claims, nil
}

func isAllowedJWSAlg(alg string) bool {
	switch alg {
	case "RS256", "RS384", "RS512", "PS256", "PS384", "PS512", "ES256", "ES384", "ES512":
		return true
	default:
		return false
	}
}

func expectedKtyForAlg(alg string) string {
	switch alg {
	case "RS256", "RS384", "RS512", "PS256", "PS384", "PS512":
		return "RSA"
	case "ES256", "ES384", "ES512":
		return "EC"
	default:
		return ""
	}
}

func selectJWK(set jwkSet, kid, alg string) (jwkKey, bool) {
	wantKty := expectedKtyForAlg(alg)
	var fallback []jwkKey
	for _, k := range set.Keys {
		if k.Use != "" && !strings.EqualFold(k.Use, "sig") {
			continue
		}
		if k.Kty != wantKty {
			continue
		}
		if k.Alg != "" && k.Alg != alg {
			continue
		}
		if kid != "" {
			if k.Kid == kid {
				return k, true
			}
			continue
		}
		fallback = append(fallback, k)
	}
	if kid == "" && len(fallback) == 1 {
		return fallback[0], true
	}
	return jwkKey{}, false
}

func verifyJWSSignature(key jwkKey, alg string, signingInput, sig []byte) error {
	switch alg {
	case "RS256", "RS384", "RS512", "PS256", "PS384", "PS512":
		pub, err := parseRSAPublicJWK(key)
		if err != nil {
			return err
		}
		hKind, hasher := hashForAlg(alg)
		_, _ = hasher.Write(signingInput)
		digest := hasher.Sum(nil)
		if strings.HasPrefix(alg, "RS") {
			if err := rsa.VerifyPKCS1v15(pub, hKind, digest, sig); err != nil {
				return errors.New("JWT RSA signature verification failed")
			}
			return nil
		}
		if err := rsa.VerifyPSS(pub, hKind, digest, sig, &rsa.PSSOptions{SaltLength: rsa.PSSSaltLengthEqualsHash}); err != nil {
			return errors.New("JWT RSA-PSS signature verification failed")
		}
		return nil

	case "ES256", "ES384", "ES512":
		pub, keySize, err := parseECDSAPublicJWK(key, alg)
		if err != nil {
			return err
		}
		if len(sig) != 2*keySize {
			return errors.New("JWT ECDSA signature has invalid length")
		}
		_, hasher := hashForAlg(alg)
		_, _ = hasher.Write(signingInput)
		digest := hasher.Sum(nil)
		r := new(big.Int).SetBytes(sig[:keySize])
		s := new(big.Int).SetBytes(sig[keySize:])
		if !ecdsa.Verify(pub, digest, r, s) {
			return errors.New("JWT ECDSA signature verification failed")
		}
		return nil

	default:
		return fmt.Errorf("unsupported JWT algorithm %q", alg)
	}
}

func hashForAlg(alg string) (crypto.Hash, hash.Hash) {
	switch alg {
	case "RS256", "PS256", "ES256":
		return crypto.SHA256, sha256.New()
	case "RS384", "PS384", "ES384":
		return crypto.SHA384, sha512.New384()
	case "RS512", "PS512", "ES512":
		return crypto.SHA512, sha512.New()
	default:
		return crypto.SHA256, sha256.New()
	}
}

func parseRSAPublicJWK(key jwkKey) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
	if err != nil || len(nBytes) == 0 {
		return nil, errors.New("invalid RSA JWK modulus")
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
	if err != nil || len(eBytes) == 0 || len(eBytes) > 8 {
		return nil, errors.New("invalid RSA JWK exponent")
	}
	n := new(big.Int).SetBytes(nBytes)
	e := int(new(big.Int).SetBytes(eBytes).Int64())
	if e < 3 || n.BitLen() < 2048 {
		return nil, errors.New("RSA JWK parameters do not meet minimum security bounds")
	}
	return &rsa.PublicKey{N: n, E: e}, nil
}

func parseECDSAPublicJWK(key jwkKey, alg string) (*ecdsa.PublicKey, int, error) {
	var (
		curve   elliptic.Curve
		wantCrv string
		keySize int
	)
	switch alg {
	case "ES256":
		curve, wantCrv, keySize = elliptic.P256(), "P-256", 32
	case "ES384":
		curve, wantCrv, keySize = elliptic.P384(), "P-384", 48
	case "ES512":
		curve, wantCrv, keySize = elliptic.P521(), "P-521", 66
	default:
		return nil, 0, fmt.Errorf("unsupported ECDSA algorithm %q", alg)
	}
	if key.Crv != wantCrv {
		return nil, 0, fmt.Errorf("ECDSA JWK curve %q does not match algorithm %s", key.Crv, alg)
	}
	xBytes, err := base64.RawURLEncoding.DecodeString(key.X)
	if err != nil || len(xBytes) == 0 {
		return nil, 0, errors.New("invalid ECDSA JWK X coordinate")
	}
	yBytes, err := base64.RawURLEncoding.DecodeString(key.Y)
	if err != nil || len(yBytes) == 0 {
		return nil, 0, errors.New("invalid ECDSA JWK Y coordinate")
	}
	x := new(big.Int).SetBytes(xBytes)
	y := new(big.Int).SetBytes(yBytes)
	if !curve.IsOnCurve(x, y) {
		return nil, 0, errors.New("ECDSA JWK point is not on curve")
	}
	return &ecdsa.PublicKey{Curve: curve, X: x, Y: y}, keySize, nil
}

func (m *Manager) verifyAndExtractIdentity(
	ctx context.Context,
	doc oidcDiscoveryDoc,
	cfg OIDCConfig,
	tok oidcTokenResponse,
	expectedNonce string,
) (StoredSession, error) {
	if strings.TrimSpace(tok.IDToken) == "" {
		return StoredSession{}, errors.New("OIDC response missing id_token")
	}
	claims, err := m.verifyJWTWithJWKS(ctx, doc.JWKSURI, tok.IDToken)
	if err != nil {
		return StoredSession{}, err
	}
	if err := validateIDTokenClaims(claims, doc.Issuer, cfg.ClientID, expectedNonce, m.now()); err != nil {
		return StoredSession{}, err
	}

	rawRoles := extractRolesFromClaims(claims, cfg.ClientID, cfg.RoleClaimKey)
	// BC Gov CSS / Keycloak may also place client_roles in a JWT access_token; merge if cryptographically verified.
	if strings.Count(tok.AccessToken, ".") == 2 {
		if accessClaims, aErr := m.verifyJWTWithJWKS(ctx, doc.JWKSURI, tok.AccessToken); aErr == nil {
			if iss, _ := accessClaims["iss"].(string); strings.TrimRight(iss, "/") == strings.TrimRight(doc.Issuer, "/") {
				rawRoles = mergeUniqueStrings(rawRoles, extractRolesFromClaims(accessClaims, cfg.ClientID, cfg.RoleClaimKey))
			}
		}
	}

	sub := claimString(claims, "sub")
	idirUser := claimString(claims, "idir_username")
	bceidUser := claimString(claims, "bceid_username")
	email := claimString(claims, "email")
	name := claimString(claims, "name")
	if name == "" {
		name = claimString(claims, "display_name")
	}
	if name == "" {
		given := claimString(claims, "given_name")
		family := claimString(claims, "family_name")
		name = strings.TrimSpace(given + " " + family)
	}

	idp := strings.ToLower(claimString(claims, "identity_provider"))
	if idp == "" {
		switch {
		case idirUser != "" || claimString(claims, "idir_user_guid") != "":
			idp = "idir"
		case bceidUser != "" || claimString(claims, "bceid_user_guid") != "":
			idp = "bceid"
		default:
			idp = "oidc"
		}
	}

	userID := firstNonEmpty(idirUser, bceidUser, claimString(claims, "preferred_username"), email, sub)
	if name == "" {
		name = userID
	}

	return StoredSession{
		Issuer:           strings.TrimRight(doc.Issuer, "/"),
		Subject:          sub,
		UserID:           userID,
		DisplayName:      name,
		Email:            email,
		Role:             MapBCGovRoles(rawRoles),
		RawRoles:         rawRoles,
		IdentityProvider: idp,
	}, nil
}

func validateIDTokenClaims(claims map[string]any, expectedIssuer, expectedClientID, expectedNonce string, now time.Time) error {
	iss := strings.TrimRight(claimString(claims, "iss"), "/")
	if iss == "" || iss != strings.TrimRight(expectedIssuer, "/") {
		return fmt.Errorf("ID token issuer mismatch: got %q", iss)
	}
	sub := claimString(claims, "sub")
	if sub == "" {
		return errors.New("ID token missing required sub claim")
	}
	if !audienceContains(claims, expectedClientID) {
		return errors.New("ID token audience does not include configured client_id")
	}
	exp, ok := claimUnixTime(claims, "exp")
	if !ok {
		return errors.New("ID token missing required exp claim")
	}
	if !now.Before(exp.Add(jwtClockSkew)) {
		return errors.New("ID token is expired")
	}
	if nbf, hasNbf := claimUnixTime(claims, "nbf"); hasNbf {
		if now.Add(jwtClockSkew).Before(nbf) {
			return errors.New("ID token is not yet valid (nbf)")
		}
	}
	if iat, hasIat := claimUnixTime(claims, "iat"); hasIat {
		if iat.After(now.Add(5 * time.Minute)) {
			return errors.New("ID token iat claim is in the future")
		}
	}
	if expectedNonce != "" {
		gotNonce := claimString(claims, "nonce")
		if subtle.ConstantTimeCompare([]byte(gotNonce), []byte(expectedNonce)) != 1 {
			return errors.New("ID token nonce mismatch")
		}
	}
	return nil
}

func audienceContains(claims map[string]any, clientID string) bool {
	rawAud, ok := claims["aud"]
	if !ok {
		return false
	}
	switch v := rawAud.(type) {
	case string:
		return v == clientID
	case []any:
		matched := false
		for _, item := range v {
			if s, ok := item.(string); ok && s == clientID {
				matched = true
				break
			}
		}
		if !matched {
			return false
		}
		// OIDC Core 3.1.3.7: if multiple audiences exist, azp must equal client_id when present.
		if len(v) > 1 {
			azp := claimString(claims, "azp")
			if azp != "" && azp != clientID {
				return false
			}
		}
		return true
	default:
		return false
	}
}

func extractRolesFromClaims(claims map[string]any, clientID, customRoleKey string) []string {
	var roles []string
	collect := func(val any) {
		switch typed := val.(type) {
		case string:
			if trimmed := strings.TrimSpace(typed); trimmed != "" {
				roles = append(roles, trimmed)
			}
		case []any:
			for _, item := range typed {
				if s, ok := item.(string); ok && strings.TrimSpace(s) != "" {
					roles = append(roles, strings.TrimSpace(s))
				}
			}
		case []string:
			for _, s := range typed {
				if trimmed := strings.TrimSpace(s); trimmed != "" {
					roles = append(roles, trimmed)
				}
			}
		}
	}

	if customRoleKey != "" {
		collect(claims[customRoleKey])
	}
	collect(claims["client_roles"])
	collect(claims["roles"])
	collect(claims["vpro_roles"])

	if realmAccess, ok := claims["realm_access"].(map[string]any); ok {
		collect(realmAccess["roles"])
	}
	if resAccess, ok := claims["resource_access"].(map[string]any); ok {
		if clientID != "" {
			if clientObj, ok := resAccess[clientID].(map[string]any); ok {
				collect(clientObj["roles"])
			}
		}
	}
	return mergeUniqueStrings(nil, roles)
}

func mergeUniqueStrings(base, extra []string) []string {
	seen := make(map[string]struct{}, len(base)+len(extra))
	out := make([]string, 0, len(base)+len(extra))
	for _, list := range [][]string{base, extra} {
		for _, item := range list {
			trimmed := strings.TrimSpace(item)
			if trimmed == "" {
				continue
			}
			if _, ok := seen[trimmed]; ok {
				continue
			}
			seen[trimmed] = struct{}{}
			out = append(out, trimmed)
		}
	}
	return out
}

func claimString(claims map[string]any, key string) string {
	val, ok := claims[key]
	if !ok || val == nil {
		return ""
	}
	s, ok := val.(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(s)
}

func claimUnixTime(claims map[string]any, key string) (time.Time, bool) {
	raw, ok := claims[key]
	if !ok || raw == nil {
		return time.Time{}, false
	}
	switch v := raw.(type) {
	case float64:
		return time.Unix(int64(v), 0).UTC(), true
	case int64:
		return time.Unix(v, 0).UTC(), true
	case json.Number:
		n, err := v.Int64()
		if err != nil {
			return time.Time{}, false
		}
		return time.Unix(n, 0).UTC(), true
	default:
		return time.Time{}, false
	}
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if trimmed := strings.TrimSpace(v); trimmed != "" {
			return trimmed
		}
	}
	return ""
}

func generatePKCEPair() (verifier, challenge string, err error) {
	verifier, err = randomURLToken(32)
	if err != nil {
		return "", "", err
	}
	sum := sha256.Sum256([]byte(verifier))
	challenge = base64.RawURLEncoding.EncodeToString(sum[:])
	return verifier, challenge, nil
}

func randomURLToken(numBytes int) (string, error) {
	buf := make([]byte, numBytes)
	if _, err := io.ReadFull(rand.Reader, buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func buildAuthorizationURL(endpoint string, cfg OIDCConfig, redirectURI, state, nonce, challenge, providerHint string) (string, error) {
	u, err := url.Parse(endpoint)
	if err != nil {
		return "", fmt.Errorf("parse authorization_endpoint: %w", err)
	}
	q := u.Query()
	q.Set("response_type", "code")
	q.Set("client_id", cfg.ClientID)
	q.Set("redirect_uri", redirectURI)
	q.Set("scope", cfg.Scopes)
	q.Set("state", state)
	q.Set("nonce", nonce)
	q.Set("code_challenge", challenge)
	q.Set("code_challenge_method", "S256")
	if providerHint != "" {
		q.Set("kc_idp_hint", providerHint)
	}
	u.RawQuery = q.Encode()
	return u.String(), nil
}

func requireHTTPSOrLoopback(rawURL string) error {
	u, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || u.Scheme == "" || u.Host == "" {
		return errors.New("invalid URL")
	}
	scheme := strings.ToLower(u.Scheme)
	if scheme == "https" {
		return nil
	}
	if scheme == "http" && isLoopbackHost(u.Hostname()) {
		return nil
	}
	return fmt.Errorf("HTTPS is required for non-loopback endpoint %q", u.Host)
}

func isLoopbackHost(host string) bool {
	h := strings.TrimSpace(strings.Trim(host, "[]"))
	if strings.EqualFold(h, "localhost") {
		return true
	}
	if addr, err := netip.ParseAddr(h); err == nil {
		return addr.IsLoopback()
	}
	return false
}

func defaultOpenBrowser(rawURL string) error {
	if err := requireHTTPSOrLoopback(rawURL); err != nil {
		return err
	}
	switch runtime.GOOS {
	case "darwin":
		return exec.Command("open", rawURL).Start()
	case "windows":
		return exec.Command("rundll32", "url.dll,FileProtocolHandler", rawURL).Start()
	default:
		return exec.Command("xdg-open", rawURL).Start()
	}
}

func renderCallbackHTML(ok bool, message string) string {
	title := "VPro Sign-In Complete"
	accent := "#003366"
	if !ok {
		title = "VPro Sign-In Problem"
		accent = "#D8292F"
	}
	return fmt.Sprintf(`<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>%s</title>
<style>
body { font-family: system-ui, -apple-system, sans-serif; background: #f2f2f2; color: #313132; margin: 0; padding: 48px 16px; }
main { max-width: 520px; margin: 0 auto; background: #fff; border-top: 4px solid %s; padding: 28px; box-shadow: 0 2px 8px rgba(0,0,0,0.08); }
h1 { margin-top: 0; font-size: 1.25rem; color: %s; }
p { line-height: 1.5; }
</style>
</head>
<body>
<main>
<h1>%s</h1>
<p>%s</p>
</main>
</body>
</html>`, html.EscapeString(title), accent, accent, html.EscapeString(title), html.EscapeString(message))
}
