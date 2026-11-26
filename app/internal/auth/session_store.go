package auth

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/google/uuid"
)

const (
	authSessionFileName = "auth_session.json"
	authSessionVersion  = 1
)

var (
	bearerTokenPattern = regexp.MustCompile(`(?i)(bearer\s+)([^\s"',;]+)`)
	jwtTokenPattern    = regexp.MustCompile(`\beyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{6,}\b`)
	kvSecretPattern    = regexp.MustCompile(`(?i)((?:access_token|refresh_token|id_token|client_secret|password|authorization)\s*[:=]\s*)([^\s"',;&]+|"[^"]*"|'[^']*')`)
	pgDSNPattern       = regexp.MustCompile(`(?i)postgres(?:ql)?://[^\s"']+`)
)

// StoredSession represents the persisted one-time machine identity and cached verified
// role claims stored on disk at <configDir>/auth_session.json with 0600 permissions.
// Token fields must never be exposed in logs, errors, or UI summaries.
type StoredSession struct {
	Version          int      `json:"version"`
	MachineID        string   `json:"machineId"`
	SignedIn         bool     `json:"signedIn"`
	Issuer           string   `json:"issuer,omitempty"`
	Subject          string   `json:"subject,omitempty"`
	UserID           string   `json:"userId,omitempty"`
	DisplayName      string   `json:"displayName,omitempty"`
	Email            string   `json:"email,omitempty"`
	Role             string   `json:"role,omitempty"`
	RawRoles         []string `json:"rawRoles,omitempty"`
	IdentityProvider string   `json:"identityProvider,omitempty"`
	IsDevEvaluation  bool     `json:"isDevEvaluation,omitempty"`
	SignedInAt       string   `json:"signedInAt,omitempty"`
	VerifiedAt       string   `json:"verifiedAt,omitempty"`
	TokenExpiresAt   string   `json:"tokenExpiresAt,omitempty"`
	LastRefreshAt    string   `json:"lastRefreshAt,omitempty"`
	AccessToken      string   `json:"accessToken,omitempty"`
	RefreshToken     string   `json:"refreshToken,omitempty"`
	IDToken          string   `json:"idToken,omitempty"`
}

// SessionSummary is the secret-free session view returned to Wails/UI and vprocore.
type SessionSummary struct {
	SignedIn               bool     `json:"signedIn"`
	MachineID              string   `json:"machineId"`
	UserID                 string   `json:"userId"`
	DisplayName            string   `json:"displayName"`
	Email                  string   `json:"email"`
	Role                   string   `json:"role"`
	RawRoles               []string `json:"rawRoles"`
	IdentityProvider       string   `json:"identityProvider"`
	Issuer                 string   `json:"issuer"`
	SignedInAt             string   `json:"signedInAt"`
	VerifiedAt             string   `json:"verifiedAt"`
	TokenExpiresAt         string   `json:"tokenExpiresAt"`
	OfflineMode            bool     `json:"offlineMode"`
	OIDCConfigured         bool     `json:"oidcConfigured"`
	DevFallbackAvailable   bool     `json:"devFallbackAvailable"`
	IsDevEvaluation        bool     `json:"isDevEvaluation"`
	CanEditWorkingProjects bool     `json:"canEditWorkingProjects"`
	CanEditBECMaster       bool     `json:"canEditBecMaster"`
}

// RedactAuthSecrets scrubs bearer tokens, JWTs, OAuth token key/values, PostgreSQL DSNs,
// and any caller-supplied secret literals from log or error messages.
func RedactAuthSecrets(msg string, extraSecrets ...string) string {
	if msg == "" {
		return ""
	}
	out := pgDSNPattern.ReplaceAllString(msg, "postgres://<redacted>")
	out = bearerTokenPattern.ReplaceAllString(out, "${1}<redacted>")
	out = jwtTokenPattern.ReplaceAllString(out, "<redacted-jwt>")
	out = kvSecretPattern.ReplaceAllString(out, "${1}<redacted>")

	var replacements []string
	for _, secret := range extraSecrets {
		trimmed := strings.TrimSpace(secret)
		if len(trimmed) < 3 {
			continue
		}
		replacements = append(replacements, trimmed, "<redacted>")
		if esc := url.QueryEscape(trimmed); esc != trimmed {
			replacements = append(replacements, esc, "<redacted>")
		}
	}
	if len(replacements) > 0 {
		out = strings.NewReplacer(replacements...).Replace(out)
	}
	return out
}

func wrapRedactedAuthError(prefix string, err error, secrets ...string) error {
	if err == nil {
		return nil
	}
	sanitized := RedactAuthSecrets(err.Error(), secrets...)
	if prefix == "" {
		return errors.New(sanitized)
	}
	return fmt.Errorf("%s: %s", prefix, sanitized)
}

func resolveConfigDir(explicit string) (string, error) {
	if trimmed := strings.TrimSpace(explicit); trimmed != "" {
		return filepath.Clean(trimmed), nil
	}
	dir, err := sqlutil.UserConfigDir()
	if err != nil {
		return "", fmt.Errorf("resolve user config directory: %w", err)
	}
	return dir, nil
}

func (m *Manager) sessionFilePath() (string, error) {
	dir, err := resolveConfigDir(m.configDir)
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, authSessionFileName), nil
}

func writeFileAtomic0600(path string, data []byte) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".vpro-auth-*.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(tmpName)
		}
	}()
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, path); err != nil {
		return err
	}
	cleanup = false
	_ = os.Chmod(path, 0o600)
	return nil
}

// loadStoredSessionLocked reads <configDir>/auth_session.json if present and ensures a stable MachineID.
func (m *Manager) loadStoredSessionLocked() (StoredSession, error) {
	if m.loaded {
		return m.session, nil
	}
	path, err := m.sessionFilePath()
	if err != nil {
		return StoredSession{}, err
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			sess := StoredSession{
				Version:   authSessionVersion,
				MachineID: uuid.NewString(),
			}
			m.session = sess
			m.loaded = true
			return sess, nil
		}
		return StoredSession{}, fmt.Errorf("read auth session store: %w", err)
	}
	var sess StoredSession
	if err := json.Unmarshal(raw, &sess); err != nil {
		// Corrupted session file fails closed (unsigned) while preserving a fresh MachineID.
		sess = StoredSession{
			Version:   authSessionVersion,
			MachineID: uuid.NewString(),
		}
		m.session = sess
		m.loaded = true
		return sess, nil
	}
	if strings.TrimSpace(sess.MachineID) == "" {
		sess.MachineID = uuid.NewString()
	}
	if sess.Version == 0 {
		sess.Version = authSessionVersion
	}
	if sess.SignedIn {
		sess.Role = NormalizeRole(sess.Role)
		if sess.Role == "" {
			sess.Role = RoleViewer
		}
		// Never trust a persisted dev-evaluation session in production builds or when OIDC is configured.
		if sess.IsDevEvaluation && !m.devFallbackAvailableLocked() {
			sess = StoredSession{
				Version:   authSessionVersion,
				MachineID: sess.MachineID,
			}
		}
	}
	m.session = sess
	m.loaded = true
	return sess, nil
}

func (m *Manager) persistStoredSessionLocked(sess StoredSession) error {
	if strings.TrimSpace(sess.MachineID) == "" {
		sess.MachineID = uuid.NewString()
	}
	sess.Version = authSessionVersion
	path, err := m.sessionFilePath()
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(sess, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	if err := writeFileAtomic0600(path, data); err != nil {
		return fmt.Errorf("write auth session store: %w", err)
	}
	m.session = sess
	m.loaded = true
	return nil
}

func (m *Manager) buildSummaryLocked(sess StoredSession, offlineMode bool) SessionSummary {
	role := NormalizeRole(sess.Role)
	if !sess.SignedIn {
		role = ""
	} else if role == "" {
		role = RoleViewer
	}
	rawRoles := append([]string(nil), sess.RawRoles...)
	if rawRoles == nil {
		rawRoles = []string{}
	}
	return SessionSummary{
		SignedIn:               sess.SignedIn,
		MachineID:              sess.MachineID,
		UserID:                 sess.UserID,
		DisplayName:            sess.DisplayName,
		Email:                  sess.Email,
		Role:                   role,
		RawRoles:               rawRoles,
		IdentityProvider:       sess.IdentityProvider,
		Issuer:                 sess.Issuer,
		SignedInAt:             sess.SignedInAt,
		VerifiedAt:             sess.VerifiedAt,
		TokenExpiresAt:         sess.TokenExpiresAt,
		OfflineMode:            offlineMode,
		OIDCConfigured:         m.oidcConfiguredLocked(),
		DevFallbackAvailable:   m.devFallbackAvailableLocked(),
		IsDevEvaluation:        sess.IsDevEvaluation,
		CanEditWorkingProjects: sess.SignedIn && RoleCanEditWorkingProject(role),
		CanEditBECMaster:       sess.SignedIn && RoleCanEditBECMaster(role),
	}
}
