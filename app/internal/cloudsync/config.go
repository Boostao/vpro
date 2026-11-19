package cloudsync

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const (
	RoleModeContributor = "contributor"
	RoleModeCustodian   = "custodian"
)

var (
	ipv4Pattern      = regexp.MustCompile(`\b\d{1,3}(?:\.\d{1,3}){3}\b`)
	pgURLPattern     = regexp.MustCompile(`(?i)postgres(?:ql)?://[^\s"']+`)
	kvPasswordRegexp = regexp.MustCompile(`(?i)(password\s*=\s*)([^\s"']+|'[^']*'|"[^"]*")`)
)

// EnvLookup resolves an environment variable key.
type EnvLookup func(key string) (string, bool)

// ResolvedCredentials holds parsed connection settings strictly in memory.
// Struct tags intentionally exclude JSON/YAML serialization to prevent accidental secret leakage.
type ResolvedCredentials struct {
	Source          string `json:"-" yaml:"-"` // "env" | "becmaster.env" | "session" | "unconfigured"
	EnvFileExists   bool   `json:"-" yaml:"-"`
	Host            string `json:"-" yaml:"-"`
	Port            uint16 `json:"-" yaml:"-"`
	Database        string `json:"-" yaml:"-"`
	SSLMode         string `json:"-" yaml:"-"`
	UserURL         string `json:"-" yaml:"-"`
	User            string `json:"-" yaml:"-"`
	UserPassword    string `json:"-" yaml:"-"`
	AdminURL        string `json:"-" yaml:"-"`
	AdminUser       string `json:"-" yaml:"-"`
	AdminPassword   string `json:"-" yaml:"-"`
	ActiveRoleMode  string `json:"-" yaml:"-"`
	SessionOverride bool   `json:"-" yaml:"-"`
}

// SessionConfigRequest updates in-memory-only role selection and optional session credential overrides.
// Never persisted to config.yml or disk.
type SessionConfigRequest struct {
	RoleMode       string `json:"roleMode"`
	ClearOverrides bool   `json:"clearOverrides,omitempty"`
	Host           string `json:"host,omitempty"`
	Port           int    `json:"port,omitempty"`
	Database       string `json:"database,omitempty"`
	SSLMode        string `json:"sslMode,omitempty"`
	User           string `json:"user,omitempty"`
	Password       string `json:"password,omitempty"`
	AdminUser      string `json:"adminUser,omitempty"`
	AdminPassword  string `json:"adminPassword,omitempty"`
}

func (r *SessionConfigRequest) UnmarshalJSON(data []byte) error {
	type plain SessionConfigRequest
	return sqlutil.DecodeStrictJSON(data, (*plain)(r))
}

// CloudConfigStatus is the secret-free status summary safe for UI and logs.
type CloudConfigStatus struct {
	Configured          bool   `json:"configured"`
	ConfigSource        string `json:"configSource"` // "env" | "becmaster.env" | "session" | "unconfigured"
	EnvFileDetected     bool   `json:"envFileDetected"`
	ActiveRoleMode      string `json:"activeRoleMode"` // "contributor" | "custodian"
	HasContributorCreds bool   `json:"hasContributorCreds"`
	HasCustodianCreds   bool   `json:"hasCustodianCreds"`
	SessionOverride     bool   `json:"sessionOverride"`
	Port                int    `json:"port"`
	Database            string `json:"database"`
	SSLMode             string `json:"sslMode"`
}

type sessionOverrides struct {
	active        bool
	host          string
	port          uint16
	database      string
	sslMode       string
	user          string
	password      string
	adminUser     string
	adminPassword string
}

// ParseDotEnvContent parses KEY=VALUE lines (with optional leading "export " and surrounding quotes).
func ParseDotEnvContent(content string) map[string]string {
	values := make(map[string]string)
	for _, rawLine := range strings.Split(content, "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimSpace(strings.TrimPrefix(line, "export "))
		idx := strings.IndexByte(line, '=')
		if idx <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:idx])
		val := strings.TrimSpace(line[idx+1:])
		if len(val) >= 2 && ((val[0] == '"' && val[len(val)-1] == '"') || (val[0] == '\'' && val[len(val)-1] == '\'')) {
			val = val[1 : len(val)-1]
		} else if hashIdx := strings.Index(val, " #"); hashIdx >= 0 {
			val = strings.TrimSpace(val[:hashIdx])
		}
		if key != "" {
			values[key] = val
		}
	}
	return values
}

// RedactSecrets scrubs passwords, hostnames, DSNs, URLs, and IPv4 addresses from diagnostic strings.
func RedactSecrets(msg string, creds *ResolvedCredentials, extraSecrets ...string) string {
	if msg == "" {
		return ""
	}
	out := pgURLPattern.ReplaceAllString(msg, "postgres://<redacted>")
	out = kvPasswordRegexp.ReplaceAllString(out, "${1}<redacted>")
	var replacements []string
	addSecret := func(val, placeholder string) {
		trimmed := strings.TrimSpace(val)
		if trimmed == "" || len(trimmed) < 2 {
			return
		}
		replacements = append(replacements, trimmed, placeholder)
		if encoded := url.QueryEscape(trimmed); encoded != trimmed {
			replacements = append(replacements, encoded, placeholder)
		}
	}
	if creds != nil {
		addSecret(creds.UserPassword, "<redacted>")
		addSecret(creds.AdminPassword, "<redacted>")
		addSecret(creds.UserURL, "postgres://<redacted>")
		addSecret(creds.AdminURL, "postgres://<redacted>")
		addSecret(creds.Host, "<pg-host>")
		for _, part := range strings.Split(creds.Host, ",") {
			addSecret(stripIPv6Brackets(part), "<pg-host>")
		}
		for _, rawU := range []string{creds.UserURL, creds.AdminURL} {
			if rawU == "" {
				continue
			}
			if parsed, err := url.Parse(rawU); err == nil {
				if h := parsed.Hostname(); h != "" {
					addSecret(h, "<pg-host>")
				}
				if parsed.User != nil {
					if pw, ok := parsed.User.Password(); ok {
						addSecret(pw, "<redacted>")
					}
				}
			}
			if pCfg, err := pgx.ParseConfig(rawU); err == nil {
				addSecret(pCfg.Host, "<pg-host>")
				for _, fb := range pCfg.Fallbacks {
					if fb != nil {
						addSecret(fb.Host, "<pg-host>")
					}
				}
				addSecret(pCfg.Password, "<redacted>")
			}
		}
	}
	for _, s := range extraSecrets {
		addSecret(s, "<redacted>")
	}
	if len(replacements) > 0 {
		out = strings.NewReplacer(replacements...).Replace(out)
	}
	out = ipv4Pattern.ReplaceAllString(out, "<redacted-ip>")
	return out
}

func wrapRedactedError(prefix string, err error, creds *ResolvedCredentials) error {
	if err == nil {
		return nil
	}
	sanitized := RedactSecrets(err.Error(), creds)
	if prefix == "" {
		return errors.New(sanitized)
	}
	return fmt.Errorf("%s: %s", prefix, sanitized)
}

// Manager manages offline-safe PostgreSQL credentials, role mode selection, and connection pools.
type Manager struct {
	mu        sync.RWMutex
	envLookup EnvLookup
	configDir string
	roleMode  string
	overrides sessionOverrides
	userPool  *pgxpool.Pool
	userKey   string
	adminPool *pgxpool.Pool
	adminKey  string
}

func NewManager(configDir string, envLookup EnvLookup) *Manager {
	if envLookup == nil {
		envLookup = os.LookupEnv
	}
	return &Manager{
		envLookup: envLookup,
		configDir: configDir,
		roleMode:  RoleModeContributor,
	}
}

func (m *Manager) Close() {
	if m == nil {
		return
	}
	m.mu.Lock()
	uPool := m.userPool
	aPool := m.adminPool
	m.userPool = nil
	m.adminPool = nil
	m.userKey = ""
	m.adminKey = ""
	m.mu.Unlock()
	if uPool != nil {
		uPool.Close()
	}
	if aPool != nil {
		aPool.Close()
	}
}

func (m *Manager) resolveEnvFilePath() string {
	dir := strings.TrimSpace(m.configDir)
	if dir == "" {
		if d, err := sqlutil.UserConfigDir(); err == nil {
			dir = d
		}
	}
	if dir == "" {
		return ""
	}
	return filepath.Join(dir, "becmaster.env")
}

// ResolveCredentials loads credentials from process env vars first, falling back to becmaster.env,
// and overlays any in-memory session overrides. Zero network calls are performed.
func (m *Manager) ResolveCredentials() (*ResolvedCredentials, error) {
	if m == nil {
		return &ResolvedCredentials{Source: "unconfigured", ActiveRoleMode: RoleModeContributor}, nil
	}
	m.mu.RLock()
	roleMode := m.roleMode
	ov := m.overrides
	envLookup := m.envLookup
	m.mu.RUnlock()

	if roleMode == "" {
		roleMode = RoleModeContributor
	}

	envPath := m.resolveEnvFilePath()
	fileVals := map[string]string{}
	envFileExists := false
	if envPath != "" {
		if raw, err := os.ReadFile(envPath); err == nil {
			envFileExists = true
			fileVals = ParseDotEnvContent(string(raw))
		}
	}

	fromEnv := false
	fromFile := false
	get := func(key string) string {
		if envLookup != nil {
			if v, ok := envLookup(key); ok && strings.TrimSpace(v) != "" {
				fromEnv = true
				return strings.TrimSpace(v)
			}
		}
		if v, ok := fileVals[key]; ok && strings.TrimSpace(v) != "" {
			fromFile = true
			return strings.TrimSpace(v)
		}
		return ""
	}

	host := get("VPRO_PG_HOST")
	portStr := get("VPRO_PG_PORT")
	dbName := get("VPRO_PG_DBNAME")
	sslMode := get("VPRO_PG_SSLMODE")
	userURL := get("VPRO_PG_URL")
	user := get("VPRO_PG_USER")
	userPass := get("VPRO_PG_PASSWORD")
	adminURL := get("VPRO_PG_ADMIN_URL")
	adminUser := get("VPRO_PG_ADMIN_USER")
	adminPass := get("VPRO_PG_ADMIN_PASSWORD")

	port := uint16(5432)
	if portStr != "" {
		parsed, err := strconv.ParseUint(portStr, 10, 16)
		if err != nil || parsed == 0 {
			return nil, errors.New("invalid VPRO_PG_PORT value (must be 1..65535)")
		}
		port = uint16(parsed)
	}
	if dbName == "" {
		dbName = "becmaster"
	}
	if sslMode == "" {
		sslMode = "require"
	}

	// Extract non-secret metadata from URLs if explicit host/port/db omitted
	applyURLDefaults := func(rawURL string, targetUser, targetPass *string) {
		if rawURL == "" {
			return
		}
		if cfg, err := pgx.ParseConfig(rawURL); err == nil {
			if host == "" {
				host = collectConfigHosts(cfg)
			}
			if portStr == "" && cfg.Port != 0 {
				port = cfg.Port
			}
			if cfg.Database != "" && get("VPRO_PG_DBNAME") == "" {
				dbName = cfg.Database
			}
			if *targetUser == "" && cfg.User != "" {
				*targetUser = cfg.User
			}
			if *targetPass == "" && cfg.Password != "" {
				*targetPass = cfg.Password
			}
		}
	}
	applyURLDefaults(userURL, &user, &userPass)
	applyURLDefaults(adminURL, &adminUser, &adminPass)

	source := "unconfigured"
	if fromEnv {
		source = "env"
	} else if fromFile {
		source = "becmaster.env"
	}

	if ov.active {
		if ov.host != "" {
			host = ov.host
			userURL = ""
			adminURL = ""
		}
		if ov.port != 0 {
			port = ov.port
			userURL = ""
			adminURL = ""
		}
		if ov.database != "" {
			dbName = ov.database
			userURL = ""
			adminURL = ""
		}
		if ov.sslMode != "" {
			sslMode = ov.sslMode
			userURL = ""
			adminURL = ""
		}
		if ov.user != "" {
			user = ov.user
			userURL = ""
		}
		if ov.password != "" {
			userPass = ov.password
			userURL = ""
		}
		if ov.adminUser != "" {
			adminUser = ov.adminUser
			adminURL = ""
		}
		if ov.adminPassword != "" {
			adminPass = ov.adminPassword
			adminURL = ""
		}
		source = "session"
	}

	return &ResolvedCredentials{
		Source:          source,
		EnvFileExists:   envFileExists,
		Host:            host,
		Port:            port,
		Database:        dbName,
		SSLMode:         sslMode,
		UserURL:         userURL,
		User:            user,
		UserPassword:    userPass,
		AdminURL:        adminURL,
		AdminUser:       adminUser,
		AdminPassword:   adminPass,
		ActiveRoleMode:  roleMode,
		SessionOverride: ov.active,
	}, nil
}

// GetConfigStatus returns a 100% offline, secret-free configuration summary.
func (m *Manager) GetConfigStatus() (CloudConfigStatus, error) {
	creds, err := m.ResolveCredentials()
	if err != nil {
		return CloudConfigStatus{}, err
	}
	hasContributor := creds.UserURL != "" || (creds.Host != "" && creds.User != "")
	hasCustodian := creds.AdminURL != "" || (creds.Host != "" && creds.AdminUser != "")
	configured := hasContributor || hasCustodian
	src := creds.Source
	if !configured {
		src = "unconfigured"
	}
	return CloudConfigStatus{
		Configured:          configured,
		ConfigSource:        src,
		EnvFileDetected:     creds.EnvFileExists,
		ActiveRoleMode:      creds.ActiveRoleMode,
		HasContributorCreds: hasContributor,
		HasCustodianCreds:   hasCustodian,
		SessionOverride:     creds.SessionOverride,
		Port:                int(creds.Port),
		Database:            creds.Database,
		SSLMode:             creds.SSLMode,
	}, nil
}

// ConfigureSession updates in-memory role selection and optional session credential overrides.
func (m *Manager) ConfigureSession(req SessionConfigRequest) (CloudConfigStatus, error) {
	if m == nil {
		return CloudConfigStatus{}, errors.New("cloud sync manager is unavailable")
	}
	mode := strings.TrimSpace(req.RoleMode)
	if mode != "" && mode != RoleModeContributor && mode != RoleModeCustodian {
		return CloudConfigStatus{}, fmt.Errorf("invalid roleMode %q (expected %q or %q)", mode, RoleModeContributor, RoleModeCustodian)
	}
	if req.Port < 0 || req.Port > 65535 {
		return CloudConfigStatus{}, errors.New("port must be between 1 and 65535")
	}
	ssl := strings.ToLower(strings.TrimSpace(req.SSLMode))
	if ssl != "" {
		switch ssl {
		case "disable", "allow", "prefer", "require", "verify-ca", "verify-full":
		default:
			return CloudConfigStatus{}, fmt.Errorf("invalid sslMode %q", req.SSLMode)
		}
	}

	m.mu.Lock()
	if mode != "" {
		m.roleMode = mode
	}
	if req.ClearOverrides {
		m.overrides = sessionOverrides{}
	}
	hasField := strings.TrimSpace(req.Host) != "" ||
		req.Port > 0 ||
		strings.TrimSpace(req.Database) != "" ||
		ssl != "" ||
		strings.TrimSpace(req.User) != "" ||
		req.Password != "" ||
		strings.TrimSpace(req.AdminUser) != "" ||
		req.AdminPassword != ""
	if hasField {
		m.overrides.active = true
		if h := strings.TrimSpace(req.Host); h != "" {
			m.overrides.host = h
		}
		if req.Port > 0 {
			m.overrides.port = uint16(req.Port)
		}
		if d := strings.TrimSpace(req.Database); d != "" {
			m.overrides.database = d
		}
		if ssl != "" {
			m.overrides.sslMode = ssl
		}
		if u := strings.TrimSpace(req.User); u != "" {
			m.overrides.user = u
		}
		if req.Password != "" {
			m.overrides.password = req.Password
		}
		if au := strings.TrimSpace(req.AdminUser); au != "" {
			m.overrides.adminUser = au
		}
		if req.AdminPassword != "" {
			m.overrides.adminPassword = req.AdminPassword
		}
	}
	// Reset cached pools whenever session credentials change
	uPool, aPool := m.userPool, m.adminPool
	if req.ClearOverrides || hasField {
		m.userPool = nil
		m.adminPool = nil
		m.userKey = ""
		m.adminKey = ""
	} else {
		uPool, aPool = nil, nil
	}
	m.mu.Unlock()

	if uPool != nil {
		uPool.Close()
	}
	if aPool != nil {
		aPool.Close()
	}
	return m.GetConfigStatus()
}

func collectConfigHosts(cfg *pgx.ConnConfig) string {
	if cfg == nil {
		return ""
	}
	seen := make(map[string]struct{}, 1+len(cfg.Fallbacks))
	var hosts []string
	addHost := func(h string) {
		trimmed := strings.TrimSpace(h)
		if trimmed == "" {
			return
		}
		if _, ok := seen[trimmed]; ok {
			return
		}
		seen[trimmed] = struct{}{}
		hosts = append(hosts, trimmed)
	}
	addHost(cfg.Host)
	for _, fb := range cfg.Fallbacks {
		if fb != nil {
			addHost(fb.Host)
		}
	}
	return strings.Join(hosts, ",")
}

type parsedPGHostTarget struct {
	host   string
	port   string
	isUnix bool
}

func isUnixSocketPGHost(host string) bool {
	if strings.HasPrefix(host, "/") {
		return true
	}
	// Match pgconn.isAbsolutePath on Windows (e.g. C:\tmp)
	if len(host) >= 3 && host[0] >= 'A' && host[0] <= 'Z' && host[1] == ':' && host[2] == '\\' {
		return true
	}
	return false
}

// stripIPv6Brackets removes a single pair of surrounding '[' and ']' from an IPv6 literal
// (e.g. "[::1]" -> "::1"). Malformed nested brackets such as "[[::1]]" are left intact so
// downstream validation rejects them.
func stripIPv6Brackets(host string) string {
	h := strings.TrimSpace(host)
	if len(h) >= 2 && h[0] == '[' && h[len(h)-1] == ']' {
		inner := h[1 : len(h)-1]
		if !strings.ContainsAny(inner, "[]") {
			return inner
		}
	}
	return h
}

func isTLSEnforcingSSLMode(sslMode string) bool {
	switch strings.ToLower(strings.TrimSpace(sslMode)) {
	case "require", "verify-ca", "verify-full":
		return true
	default:
		return false
	}
}

func parsePGHostSegments(rawHost string, defaultPort uint16) ([]parsedPGHostTarget, error) {
	if strings.TrimSpace(rawHost) == "" {
		return nil, errors.New("PostgreSQL host is empty")
	}
	defaultPortStr := strconv.Itoa(int(defaultPort))
	rawParts := strings.Split(rawHost, ",")
	targets := make([]parsedPGHostTarget, 0, len(rawParts))
	for _, rawPart := range rawParts {
		part := strings.TrimSpace(rawPart)
		if part == "" {
			return nil, errors.New("invalid PostgreSQL host: empty entry in comma-separated host list")
		}
		if isUnixSocketPGHost(part) {
			targets = append(targets, parsedPGHostTarget{
				host:   part,
				port:   defaultPortStr,
				isUnix: true,
			})
			continue
		}
		if strings.HasPrefix(part, "[") {
			if strings.HasSuffix(part, "]") {
				inner := part[1 : len(part)-1]
				if inner == "" || strings.ContainsAny(inner, "[]") {
					return nil, errors.New("invalid bracketed IPv6 PostgreSQL host")
				}
				if addr, err := netip.ParseAddr(inner); err != nil || !addr.Is6() {
					return nil, errors.New("invalid bracketed IPv6 PostgreSQL host")
				}
				targets = append(targets, parsedPGHostTarget{
					host: inner,
					port: defaultPortStr,
				})
				continue
			}
			h, p, err := net.SplitHostPort(part)
			if err != nil || h == "" || strings.ContainsAny(h, "[]") {
				return nil, errors.New("invalid bracketed IPv6 PostgreSQL host:port")
			}
			if addr, err := netip.ParseAddr(h); err != nil || !addr.Is6() {
				return nil, errors.New("invalid bracketed IPv6 PostgreSQL host")
			}
			parsedP, err := strconv.ParseUint(p, 10, 16)
			if err != nil || parsedP == 0 {
				return nil, errors.New("invalid port in PostgreSQL host")
			}
			targets = append(targets, parsedPGHostTarget{
				host: h,
				port: strconv.FormatUint(parsedP, 10),
			})
			continue
		}
		if strings.ContainsAny(part, "[]") {
			return nil, errors.New("invalid bracket characters in PostgreSQL host")
		}
		if strings.Count(part, ":") == 1 {
			h, p, err := net.SplitHostPort(part)
			if err != nil || strings.TrimSpace(h) == "" {
				return nil, errors.New("invalid PostgreSQL host:port")
			}
			parsedP, err := strconv.ParseUint(p, 10, 16)
			if err != nil || parsedP == 0 {
				return nil, errors.New("invalid port in PostgreSQL host")
			}
			targets = append(targets, parsedPGHostTarget{
				host: h,
				port: strconv.FormatUint(parsedP, 10),
			})
			continue
		}
		if strings.Count(part, ":") >= 2 {
			if addr, err := netip.ParseAddr(part); err != nil || !addr.Is6() {
				return nil, errors.New("invalid IPv6 PostgreSQL host")
			}
		}
		targets = append(targets, parsedPGHostTarget{
			host: part,
			port: defaultPortStr,
		})
	}
	return targets, nil
}

func buildConnURLStringForRole(creds *ResolvedCredentials, roleMode string) (string, error) {
	if creds == nil {
		return "", errors.New("PostgreSQL credentials are not configured")
	}
	isCustodian := roleMode == RoleModeCustodian
	rawURL := creds.UserURL
	user := creds.User
	pass := creds.UserPassword
	missingMsg := "PostgreSQL contributor credentials are not configured (set VPRO_PG_HOST/VPRO_PG_USER/VPRO_PG_PASSWORD or ~/.config/vpro/becmaster.env)"
	if isCustodian {
		rawURL = creds.AdminURL
		user = creds.AdminUser
		pass = creds.AdminPassword
		missingMsg = "PostgreSQL custodian admin credentials are not configured (set VPRO_PG_ADMIN_USER/VPRO_PG_ADMIN_PASSWORD or ~/.config/vpro/becmaster.env)"
	}
	if rawURL != "" {
		if preCfg, preErr := pgx.ParseConfig(rawURL); preErr == nil {
			if tlsErr := requireTLSForRemoteHost(preCfg); tlsErr != nil {
				return "", tlsErr
			}
		}
		return rawURL, nil
	}
	if strings.TrimSpace(creds.Host) == "" || user == "" {
		return "", errors.New(missingMsg)
	}
	ssl := strings.ToLower(strings.TrimSpace(creds.SSLMode))
	if ssl == "" {
		ssl = "require"
	}
	port := creds.Port
	if port == 0 {
		port = 5432
	}
	db := creds.Database
	if db == "" {
		db = "becmaster"
	}

	targets, err := parsePGHostSegments(creds.Host, port)
	if err != nil {
		return "", wrapRedactedError("parse PostgreSQL host", err, creds)
	}
	if !isTLSEnforcingSSLMode(ssl) {
		for _, target := range targets {
			if !isLoopbackPGHost(target.host) {
				return "", errRemotePlaintext
			}
		}
	}

	q := url.Values{}
	q.Set("sslmode", ssl)
	var urlHost string
	if len(targets) == 1 && !targets[0].isUnix && !strings.ContainsRune(targets[0].host, '%') {
		urlHost = net.JoinHostPort(targets[0].host, targets[0].port)
	} else {
		hosts := make([]string, len(targets))
		ports := make([]string, len(targets))
		for i, target := range targets {
			hosts[i] = target.host
			ports[i] = target.port
		}
		q.Set("host", strings.Join(hosts, ","))
		q.Set("port", strings.Join(ports, ","))
	}
	u := &url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(user, pass),
		Host:     urlHost,
		Path:     "/" + db,
		RawQuery: q.Encode(),
	}
	return u.String(), nil
}

func buildConnConfigForRole(creds *ResolvedCredentials, roleMode string) (*pgx.ConnConfig, error) {
	connStr, err := buildConnURLStringForRole(creds, roleMode)
	if err != nil {
		return nil, err
	}
	cfg, err := pgx.ParseConfig(connStr)
	if err != nil {
		return nil, wrapRedactedError("parse PostgreSQL connection config", err, creds)
	}
	if err := requireTLSForRemoteHost(cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}

// errRemotePlaintext is returned when a non-loopback PostgreSQL host is configured with an
// sslmode (disable, allow, prefer) that permits an unencrypted connection.
var errRemotePlaintext = errors.New("TLS is required for remote PostgreSQL hosts: set sslmode to require, verify-ca or verify-full (disable, allow and prefer are only permitted for localhost)")

// requireTLSForRemoteHost rejects connection configs that could send credentials or plot data in
// plaintext to a non-loopback host. pgx represents sslmode=disable as a nil TLSConfig and
// allow/prefer/multi-host as FallbackConfig entries, so BOTH the primary config AND every
// fallback entry are checked unconditionally (even when the primary host is loopback or a Unix socket).
func requireTLSForRemoteHost(cfg *pgx.ConnConfig) error {
	if cfg == nil {
		return nil
	}
	hasRemoteHostAddr := false
	if hostAddr := strings.TrimSpace(cfg.RuntimeParams["hostaddr"]); hostAddr != "" && !isLoopbackPGHost(hostAddr) {
		hasRemoteHostAddr = true
	}
	if (hasRemoteHostAddr || !isLoopbackPGHost(cfg.Host)) && cfg.TLSConfig == nil {
		return errRemotePlaintext
	}
	for _, fb := range cfg.Fallbacks {
		if fb == nil {
			continue
		}
		if (hasRemoteHostAddr || !isLoopbackPGHost(fb.Host)) && fb.TLSConfig == nil {
			return errRemotePlaintext
		}
	}
	return nil
}

func isLoopbackPGHost(host string) bool {
	h := strings.TrimSpace(host)
	if h == "" {
		return true
	}
	if strings.ContainsRune(h, ',') {
		for _, part := range strings.Split(h, ",") {
			trimmed := strings.TrimSpace(part)
			if trimmed == "" || !isSingleLoopbackPGHost(trimmed) {
				return false
			}
		}
		return true
	}
	return isSingleLoopbackPGHost(h)
}

func isSingleLoopbackPGHost(host string) bool {
	h := strings.TrimSpace(host)
	if h == "" {
		return true
	}
	if strings.ContainsRune(h, ',') {
		return false
	}
	if isUnixSocketPGHost(h) {
		return true
	}
	if strings.EqualFold(h, "localhost") {
		return true
	}
	unbracketed := stripIPv6Brackets(h)
	if strings.ContainsAny(unbracketed, "[]") {
		return false
	}
	addr, err := netip.ParseAddr(unbracketed)
	return err == nil && addr.Unmap().IsLoopback()
}

// ErrDestructiveDBUnconfirmed indicates that a disposable test database was configured,
// but VPRO_LIVE_PG_DESTRUCTIVE_DB was not set to confirm destructive execution.
var ErrDestructiveDBUnconfirmed = errors.New("VPRO_LIVE_PG_DESTRUCTIVE_DB confirmation is not set")

// IsDisposableTestDatabaseName returns true only when dbName explicitly identifies an isolated
// test/QA/scratch/disposable database and is never a production-like or PostgreSQL system database
// (such as "becmaster", "postgres", "template0", "template1", or "becmaster_latest").
func IsDisposableTestDatabaseName(dbName string) bool {
	trimmed := strings.TrimSpace(dbName)
	if trimmed == "" {
		return false
	}
	lower := strings.ToLower(trimmed)
	switch lower {
	case "becmaster", "bec_master", "postgres", "template0", "template1", "defaultdb", "master", "prod", "production", "staging", "vpro":
		return false
	}
	tokens := strings.FieldsFunc(lower, func(r rune) bool {
		return !(r >= 'a' && r <= 'z') && !(r >= '0' && r <= '9')
	})
	if len(tokens) == 0 {
		return false
	}
	hasTestMarker := false
	for _, tok := range tokens {
		switch tok {
		case "prod", "production", "template0", "template1":
			return false
		case "test", "tests", "testing", "qa", "tmp", "temp", "scratch", "disposable", "ephemeral",
			"testdb", "qadb", "tmpdb", "tempdb", "scratchdb",
			"vprotest", "becmastertest", "becmasterqa", "becmastertmp", "becmasterscratch":
			hasTestMarker = true
		default:
			for _, prefix := range []string{"test", "qa", "tmp", "temp", "scratch", "disposable"} {
				if strings.HasPrefix(tok, prefix) && isAllASCIIDigits(tok[len(prefix):]) {
					hasTestMarker = true
					break
				}
			}
		}
	}
	return hasTestMarker
}

func isAllASCIIDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// ValidateDestructiveTestDatabase refuses destructive live PostgreSQL tests unless every resolved
// target database (field/env Database plus UserURL and AdminURL) is a disposable test/QA/scratch
// database AND matches confirmedDB (from VPRO_LIVE_PG_DESTRUCTIVE_DB).
func ValidateDestructiveTestDatabase(creds *ResolvedCredentials, confirmedDB string) error {
	if creds == nil {
		return errors.New("PostgreSQL credentials are not configured")
	}
	primaryDB := strings.TrimSpace(creds.Database)
	if !IsDisposableTestDatabaseName(primaryDB) {
		return fmt.Errorf(
			"refusing destructive PostgreSQL test against database %q: must be an isolated test/qa/tmp/scratch/disposable database (never becmaster, postgres, template0, template1, or a production database)",
			primaryDB,
		)
	}
	checkRoleURLDB := func(label, rawURL string) error {
		if strings.TrimSpace(rawURL) == "" {
			return nil
		}
		uCfg, err := pgx.ParseConfig(rawURL)
		if err != nil {
			return wrapRedactedError("parse "+label+" PostgreSQL URL", err, creds)
		}
		roleDB := strings.TrimSpace(uCfg.Database)
		if roleDB == "" {
			roleDB = strings.TrimSpace(uCfg.User)
		}
		if !IsDisposableTestDatabaseName(roleDB) {
			return fmt.Errorf(
				"refusing destructive PostgreSQL test against %s URL database %q: must be an isolated test/qa/tmp/scratch/disposable database",
				label,
				roleDB,
			)
		}
		if roleDB != primaryDB {
			return fmt.Errorf("%s URL database %q does not match configured database %q", label, roleDB, primaryDB)
		}
		return nil
	}
	if err := checkRoleURLDB("contributor", creds.UserURL); err != nil {
		return err
	}
	if err := checkRoleURLDB("custodian", creds.AdminURL); err != nil {
		return err
	}

	confirmed := strings.TrimSpace(confirmedDB)
	if confirmed == "" {
		return fmt.Errorf("%w: set VPRO_LIVE_PG_DESTRUCTIVE_DB=%s to confirm %q is a disposable test database", ErrDestructiveDBUnconfirmed, primaryDB, primaryDB)
	}
	if !IsDisposableTestDatabaseName(confirmed) {
		return fmt.Errorf(
			"refusing destructive PostgreSQL test with VPRO_LIVE_PG_DESTRUCTIVE_DB=%q: must name an isolated test/qa/tmp/scratch/disposable database",
			confirmed,
		)
	}
	if confirmed != primaryDB {
		return fmt.Errorf("VPRO_LIVE_PG_DESTRUCTIVE_DB=%q does not match configured test database %q", confirmed, primaryDB)
	}
	return nil
}
