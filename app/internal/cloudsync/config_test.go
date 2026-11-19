package cloudsync

import (
	"context"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestConfigMultiHostAndIPv6LoopbackTLSEnforcement(t *testing.T) {
	cases := []struct {
		name        string
		creds       ResolvedCredentials
		role        string
		wantTLSErr  bool
		wantAnyErr  bool
		wantURLSub  string
		forbidSub   string
		wantCfgHost string
	}{
		// Bracketed and unbracketed IPv6 loopback on field/UI path
		{
			name:        "field bracketed [::1] disable",
			creds:       ResolvedCredentials{Host: "[::1]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantURLSub:  "@[::1]:5432/",
			forbidSub:   "[[::1]]",
			wantCfgHost: "::1",
		},
		{
			name:        "field bracketed [::1] prefer",
			creds:       ResolvedCredentials{Host: " [::1] ", Port: 5433, User: "u", UserPassword: "p", SSLMode: "prefer"},
			wantURLSub:  "@[::1]:5433/",
			forbidSub:   "[[::1]]",
			wantCfgHost: "::1",
		},
		{
			name:        "field unbracketed ::1 disable",
			creds:       ResolvedCredentials{Host: "::1", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantURLSub:  "@[::1]:5432/",
			forbidSub:   "[[::1]]",
			wantCfgHost: "::1",
		},
		{
			name:        "field expanded IPv6 loopback [0:0:0:0:0:0:0:1] disable",
			creds:       ResolvedCredentials{Host: "[0:0:0:0:0:0:0:1]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantURLSub:  "@[0:0:0:0:0:0:0:1]:5432/",
			forbidSub:   "[[",
			wantCfgHost: "0:0:0:0:0:0:0:1",
		},
		{
			name:        "field IPv4-mapped IPv6 loopback [::ffff:127.0.0.1] disable",
			creds:       ResolvedCredentials{Host: "[::ffff:127.0.0.1]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantURLSub:  "@[::ffff:127.0.0.1]:5432/",
			forbidSub:   "[[",
			wantCfgHost: "::ffff:127.0.0.1",
		},
		{
			name:        "field bracketed [::1]:5434 explicit port disable",
			creds:       ResolvedCredentials{Host: "[::1]:5434", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantURLSub:  "@[::1]:5434/",
			forbidSub:   "[[",
			wantCfgHost: "::1",
		},
		{
			name:        "field zone-scoped IPv6 loopback [::1%lo] disable",
			creds:       ResolvedCredentials{Host: "[::1%lo]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantCfgHost: "::1%lo",
		},
		{
			name:       "field malformed double-bracket [[::1]] rejected",
			creds:      ResolvedCredentials{Host: "[[::1]]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantAnyErr: true,
		},
		// Loopback IPv4, localhost, and Unix domain sockets
		{
			name:        "field 127.0.0.1 disable",
			creds:       ResolvedCredentials{Host: "127.0.0.1", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantURLSub:  "@127.0.0.1:5432/",
			wantCfgHost: "127.0.0.1",
		},
		{
			name:        "field 127.0.0.42 allow",
			creds:       ResolvedCredentials{Host: "127.0.0.42", Port: 5432, User: "u", UserPassword: "p", SSLMode: "allow"},
			wantCfgHost: "127.0.0.42",
		},
		{
			name:        "field localhost disable",
			creds:       ResolvedCredentials{Host: "LOCALHOST", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantCfgHost: "LOCALHOST",
		},
		{
			name:        "field unix socket /tmp disable",
			creds:       ResolvedCredentials{Host: "/tmp", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantCfgHost: "/tmp",
		},
		{
			name:        "field unix socket /var/run/postgresql prefer",
			creds:       ResolvedCredentials{Host: "/var/run/postgresql", Port: 5432, User: "u", UserPassword: "p", SSLMode: "prefer"},
			wantCfgHost: "/var/run/postgresql",
		},
		// Bogus loopback-looking strings and unspecified addresses must require TLS
		{
			name:       "field bogus 127.999.999.999 disable rejected",
			creds:      ResolvedCredentials{Host: "127.999.999.999", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantTLSErr: true,
		},
		{
			name:       "field unspecified 0.0.0.0 disable rejected",
			creds:      ResolvedCredentials{Host: "0.0.0.0", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantTLSErr: true,
		},
		{
			name:       "field unspecified [::] disable rejected",
			creds:      ResolvedCredentials{Host: "[::]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantTLSErr: true,
		},
		// Remote IPv6 & DNS hosts
		{
			name:       "field bracketed remote IPv6 [2001:db8::1] disable rejected",
			creds:      ResolvedCredentials{Host: "[2001:db8::1]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantTLSErr: true,
		},
		{
			name:       "field bracketed remote IPv6 [2001:db8::1] prefer rejected",
			creds:      ResolvedCredentials{Host: "[2001:db8::1]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "prefer"},
			wantTLSErr: true,
		},
		{
			name:        "field bracketed remote IPv6 [2001:db8::1] require accepted",
			creds:       ResolvedCredentials{Host: "[2001:db8::1]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "require"},
			wantURLSub:  "@[2001:db8::1]:5432/",
			forbidSub:   "[[",
			wantCfgHost: "2001:db8::1",
		},
		// Multi-host plaintext bypass attempts on field/UI path
		{
			name:       "field multi-host 127.0.0.1,db.example.org disable rejected",
			creds:      ResolvedCredentials{Host: "127.0.0.1,db.example.org", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantTLSErr: true,
		},
		{
			name:       "field multi-host 127.0.0.1,db.example.org allow rejected",
			creds:      ResolvedCredentials{Host: "127.0.0.1,db.example.org", Port: 5432, User: "u", UserPassword: "p", SSLMode: "allow"},
			wantTLSErr: true,
		},
		{
			name:       "field multi-host 127.0.0.1,db.example.org prefer rejected",
			creds:      ResolvedCredentials{Host: "127.0.0.1,db.example.org", Port: 5432, User: "u", UserPassword: "p", SSLMode: "prefer"},
			wantTLSErr: true,
		},
		{
			name:       "field multi-host /tmp,db.example.org disable rejected",
			creds:      ResolvedCredentials{Host: "/tmp,db.example.org", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantTLSErr: true,
		},
		{
			name:       "field multi-host /tmp,db.example.org prefer rejected",
			creds:      ResolvedCredentials{Host: "/tmp,db.example.org", Port: 5432, User: "u", UserPassword: "p", SSLMode: "prefer"},
			wantTLSErr: true,
		},
		{
			name:       "field multi-host [::1],db.example.org disable rejected",
			creds:      ResolvedCredentials{Host: "[::1],db.example.org", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantTLSErr: true,
		},
		{
			name:       "field multi-host ::1,203.0.113.10 allow rejected",
			creds:      ResolvedCredentials{Host: "::1,203.0.113.10", Port: 5432, User: "u", UserPassword: "p", SSLMode: "allow"},
			wantTLSErr: true,
		},
		{
			name:        "field multi-host 127.0.0.1,db.example.org require accepted",
			creds:       ResolvedCredentials{Host: "127.0.0.1,db.example.org", Port: 5432, User: "u", UserPassword: "p", SSLMode: "require"},
			wantCfgHost: "127.0.0.1",
		},
		{
			name:        "field multi-host /tmp,db.example.org require accepted",
			creds:       ResolvedCredentials{Host: "/tmp,db.example.org", Port: 5432, User: "u", UserPassword: "p", SSLMode: "require"},
			wantCfgHost: "/tmp",
		},
		{
			name:        "field multi-host loopback-only 127.0.0.1,[::1] disable accepted",
			creds:       ResolvedCredentials{Host: "127.0.0.1,[::1]", Port: 5432, User: "u", UserPassword: "p", SSLMode: "disable"},
			wantCfgHost: "127.0.0.1",
		},
		// Multi-host plaintext bypass attempts on URL / DSN path (Contributor & Custodian)
		{
			name:       "url multi-host 127.0.0.1,db.example.org disable rejected",
			creds:      ResolvedCredentials{UserURL: "postgres://u:p@127.0.0.1:5432,db.example.org:5432/becmaster?sslmode=disable"},
			wantTLSErr: true,
		},
		{
			name:       "url multi-host 127.0.0.1,db.example.org prefer rejected",
			creds:      ResolvedCredentials{UserURL: "postgres://u:p@127.0.0.1:5432,db.example.org:5432/becmaster?sslmode=prefer"},
			wantTLSErr: true,
		},
		{
			name:       "url multi-host 127.0.0.1,db.example.org allow rejected",
			creds:      ResolvedCredentials{UserURL: "postgres://u:p@127.0.0.1:5432,db.example.org:5432/becmaster?sslmode=allow"},
			wantTLSErr: true,
		},
		{
			name:       "url multi-host 127.0.0.1,db.example.org default sslmode (prefer) rejected",
			creds:      ResolvedCredentials{UserURL: "postgres://u:p@127.0.0.1:5432,db.example.org:5432/becmaster"},
			wantTLSErr: true,
		},
		{
			name:       "url multi-host [::1],[2001:db8::1] disable rejected",
			creds:      ResolvedCredentials{UserURL: "postgres://u:p@[::1]:5432,[2001:db8::1]:5432/becmaster?sslmode=disable"},
			wantTLSErr: true,
		},
		{
			name:       "url query multi-host /tmp,db.example.org disable rejected",
			creds:      ResolvedCredentials{UserURL: "postgres://u:p@/becmaster?host=/tmp,db.example.org&sslmode=disable"},
			wantTLSErr: true,
		},
		{
			name:       "url percent-encoded /tmp,db.example.org disable rejected",
			creds:      ResolvedCredentials{UserURL: "postgres://u:p@%2Ftmp:5432,db.example.org:5432/becmaster?sslmode=disable"},
			wantTLSErr: true,
		},
		{
			name:       "dsn keyword-value /tmp,db.example.org prefer rejected",
			creds:      ResolvedCredentials{UserURL: "host=/tmp,db.example.org user=u password=p dbname=becmaster sslmode=prefer"},
			wantTLSErr: true,
		},
		{
			name:       "custodian url multi-host 127.0.0.1,db.example.org disable rejected",
			creds:      ResolvedCredentials{AdminURL: "postgres://admin:p@127.0.0.1:5432,db.example.org:5432/becmaster?sslmode=disable"},
			role:       RoleModeCustodian,
			wantTLSErr: true,
		},
		{
			name:       "url loopback host with remote hostaddr prefer rejected",
			creds:      ResolvedCredentials{UserURL: "postgres://u:p@localhost:5432/becmaster?hostaddr=203.0.113.10&sslmode=prefer"},
			wantTLSErr: true,
		},
		{
			name:        "url multi-host 127.0.0.1,db.example.org require accepted",
			creds:       ResolvedCredentials{UserURL: "postgres://u:p@127.0.0.1:5432,db.example.org:5432/becmaster?sslmode=require"},
			wantCfgHost: "127.0.0.1",
		},
		{
			name:        "url multi-host loopback-only 127.0.0.1,[::1] disable accepted",
			creds:       ResolvedCredentials{UserURL: "postgres://u:p@127.0.0.1:5432,[::1]:5432/becmaster?sslmode=disable"},
			wantCfgHost: "127.0.0.1",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			role := tc.role
			if role == "" {
				role = RoleModeContributor
			}
			creds := tc.creds
			urlStr, urlErr := buildConnURLStringForRole(&creds, role)
			cfg, cfgErr := buildConnConfigForRole(&creds, role)

			if tc.wantTLSErr {
				if !errors.Is(cfgErr, errRemotePlaintext) {
					t.Fatalf("expected errRemotePlaintext from buildConnConfigForRole, got %v", cfgErr)
				}
				return
			}
			if tc.wantAnyErr {
				if cfgErr == nil {
					t.Fatalf("expected error from buildConnConfigForRole, got nil (url=%q)", urlStr)
				}
				return
			}
			if urlErr != nil || cfgErr != nil {
				t.Fatalf("expected success, got urlErr=%v cfgErr=%v (url=%q)", urlErr, cfgErr, urlStr)
			}
			if tc.wantURLSub != "" && !strings.Contains(urlStr, tc.wantURLSub) {
				t.Fatalf("expected URL %q to contain %q", urlStr, tc.wantURLSub)
			}
			if tc.forbidSub != "" && strings.Contains(urlStr, tc.forbidSub) {
				t.Fatalf("URL %q must not contain %q", urlStr, tc.forbidSub)
			}
			if tc.wantCfgHost != "" && cfg.Host != tc.wantCfgHost {
				t.Fatalf("expected parsed cfg.Host=%q, got %q", tc.wantCfgHost, cfg.Host)
			}
		})
	}

	// Direct unit checks on isLoopbackPGHost with comma-separated inputs
	for _, nonLoop := range []string{
		"/tmp,db.example.org",
		"127.0.0.1,db.example.org",
		"[::1],db.example.org",
		"localhost,203.0.113.10",
		"127.0.0.1,",
		",127.0.0.1",
		"127.999.999.999",
		"[[::1]]",
	} {
		if isLoopbackPGHost(nonLoop) {
			t.Fatalf("isLoopbackPGHost(%q) = true, want false", nonLoop)
		}
	}
	for _, loop := range []string{
		"127.0.0.1",
		"::1",
		"[::1]",
		"0:0:0:0:0:0:0:1",
		"[0:0:0:0:0:0:0:1]",
		"::ffff:127.0.0.1",
		"[::ffff:127.0.0.1]",
		"localhost",
		"/tmp",
		"/var/run/postgresql",
		"127.0.0.1,[::1],/tmp",
	} {
		if !isLoopbackPGHost(loop) {
			t.Fatalf("isLoopbackPGHost(%q) = false, want true", loop)
		}
	}
}

func TestConfigPoolAndDedicatedConnRejectMultiHostPlaintextWithZeroTCPConnections(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	var tcpConns atomic.Int64
	go func() {
		for {
			c, acceptErr := ln.Accept()
			if acceptErr != nil {
				return
			}
			tcpConns.Add(1)
			_ = c.Close()
		}
	}()

	_, portStr, err := net.SplitHostPort(ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	port, err := strconv.Atoi(portStr)
	if err != nil {
		t.Fatal(err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	// 1. UI/Session field multi-host bypass attempt
	mgrField := NewManager(t.TempDir(), func(string) (string, bool) { return "", false })
	defer mgrField.Close()
	if _, err := mgrField.ConfigureSession(SessionConfigRequest{
		RoleMode:      RoleModeCustodian,
		Host:          "127.0.0.1,db.example.org",
		Port:          port,
		Database:      "becmaster_test",
		SSLMode:       "disable",
		User:          "u",
		Password:      "p",
		AdminUser:     "admin",
		AdminPassword: "p",
	}); err != nil {
		t.Fatal(err)
	}
	if _, _, err := mgrField.AcquirePool(ctx, RoleModeContributor); !errors.Is(err, errRemotePlaintext) {
		t.Fatalf("AcquirePool must reject multi-host plaintext with errRemotePlaintext, got %v", err)
	}
	if _, _, err := mgrField.OpenDedicatedConn(ctx, RoleModeCustodian); !errors.Is(err, errRemotePlaintext) {
		t.Fatalf("OpenDedicatedConn must reject multi-host plaintext with errRemotePlaintext, got %v", err)
	}
	if _, err := mgrField.TestCloudConnection(ctx); !errors.Is(err, errRemotePlaintext) {
		t.Fatalf("TestCloudConnection must reject multi-host plaintext with errRemotePlaintext, got %v", err)
	}
	if _, err := mgrField.BootstrapSchemas(ctx); !errors.Is(err, errRemotePlaintext) {
		t.Fatalf("BootstrapSchemas must reject multi-host plaintext with errRemotePlaintext, got %v", err)
	}

	// 2. URL multi-host bypass attempt (even when primary target is the live local listener!)
	multiURL := "postgres://u:p@127.0.0.1:" + portStr + ",db.example.org:" + portStr + "/becmaster_test?sslmode=prefer"
	mgrURL := NewManager(t.TempDir(), func(key string) (string, bool) {
		if key == "VPRO_PG_URL" || key == "VPRO_PG_ADMIN_URL" {
			return multiURL, true
		}
		return "", false
	})
	defer mgrURL.Close()
	if _, _, err := mgrURL.AcquirePool(ctx, RoleModeContributor); !errors.Is(err, errRemotePlaintext) {
		t.Fatalf("AcquirePool(URL multi-host prefer) must reject with errRemotePlaintext, got %v", err)
	}
	if _, _, err := mgrURL.OpenDedicatedConn(ctx, RoleModeCustodian); !errors.Is(err, errRemotePlaintext) {
		t.Fatalf("OpenDedicatedConn(URL multi-host prefer) must reject with errRemotePlaintext, got %v", err)
	}

	if got := tcpConns.Load(); got != 0 {
		t.Fatalf("expected 0 TCP connections on rejected multi-host plaintext configs, got %d", got)
	}
}

func TestResolveCredentialsPreservesMultiHostURLOnSessionSSLOverride(t *testing.T) {
	mgr := NewManager(t.TempDir(), func(key string) (string, bool) {
		if key == "VPRO_PG_URL" {
			return "postgres://u:SecretPass!1@127.0.0.1:5432,db.example.org:5432/becmaster?sslmode=require", true
		}
		return "", false
	})
	defer mgr.Close()

	// Overriding only SSLMode="disable" in session must NOT drop db.example.org from Host!
	if _, err := mgr.ConfigureSession(SessionConfigRequest{SSLMode: "disable"}); err != nil {
		t.Fatal(err)
	}
	creds, err := mgr.ResolveCredentials()
	if err != nil {
		t.Fatal(err)
	}
	if creds.Host != "127.0.0.1,db.example.org" {
		t.Fatalf("expected multi-host preserved in creds.Host, got %q", creds.Host)
	}
	if _, err := buildConnConfigForRole(creds, RoleModeContributor); !errors.Is(err, errRemotePlaintext) {
		t.Fatalf("expected session sslmode=disable override on multi-host URL to fail with errRemotePlaintext, got %v", err)
	}

	redacted := RedactSecrets("dial failed for db.example.org with SecretPass!1", creds)
	if strings.Contains(redacted, "db.example.org") || strings.Contains(redacted, "SecretPass!1") {
		t.Fatalf("RedactSecrets leaked multi-host secret/hostname: %q", redacted)
	}
}

func TestConfigDisposableTestDatabaseValidation(t *testing.T) {
	rejectedDBs := []string{
		"",
		"becmaster",
		"BECMaster",
		"bec_master",
		"postgres",
		"template0",
		"template1",
		"defaultdb",
		"master",
		"prod",
		"production",
		"staging",
		"vpro",
		"becmaster_v13",
		"becmaster_2026",
		"becmaster_latest",
		"becmaster_contest",
		"becmaster_prod",
		"becmaster_prod_test",
	}
	for _, db := range rejectedDBs {
		if IsDisposableTestDatabaseName(db) {
			t.Fatalf("IsDisposableTestDatabaseName(%q) = true, want false", db)
		}
		creds := &ResolvedCredentials{Database: db}
		// Must reject EVEN WHEN VPRO_LIVE_PG_DESTRUCTIVE_DB matches creds.Database!
		if err := ValidateDestructiveTestDatabase(creds, db); err == nil {
			t.Fatalf("ValidateDestructiveTestDatabase(%q, %q) = nil, want error", db, db)
		}
	}

	acceptedDBs := []string{
		"becmaster_test",
		"BECMASTER_TEST",
		"test_becmaster",
		"becmaster_qa",
		"qa_becmaster",
		"becmaster_tmp",
		"becmaster_temp",
		"becmaster_scratch",
		"becmaster_disposable",
		"vpro_test_01",
		"vpro_qa2",
		"testdb",
	}
	for _, db := range acceptedDBs {
		if !IsDisposableTestDatabaseName(db) {
			t.Fatalf("IsDisposableTestDatabaseName(%q) = false, want true", db)
		}
		creds := &ResolvedCredentials{Database: db}
		if err := ValidateDestructiveTestDatabase(creds, db); err != nil {
			t.Fatalf("ValidateDestructiveTestDatabase(%q, %q) unexpected error: %v", db, db, err)
		}
		if err := ValidateDestructiveTestDatabase(creds, ""); !errors.Is(err, ErrDestructiveDBUnconfirmed) {
			t.Fatalf("expected ErrDestructiveDBUnconfirmed for empty confirmation on %q, got %v", db, err)
		}
		if err := ValidateDestructiveTestDatabase(creds, "other_test"); err == nil {
			t.Fatalf("expected mismatch error for %q vs other_test", db)
		}
	}

	// URL database spoofing check: Database="becmaster_test" but AdminURL points to "/becmaster"
	spoofCreds := &ResolvedCredentials{
		Database: "becmaster_test",
		UserURL:  "postgres://u:p@127.0.0.1:5432/becmaster_test?sslmode=disable",
		AdminURL: "postgres://admin:p@127.0.0.1:5432/becmaster?sslmode=disable",
	}
	if err := ValidateDestructiveTestDatabase(spoofCreds, "becmaster_test"); err == nil {
		t.Fatal("expected ValidateDestructiveTestDatabase to reject AdminURL targeting production becmaster")
	}
}

func TestLiveOptInGateSkipsWithZeroTCPConnectionsWhenUnset(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()

	var tcpConns atomic.Int64
	go func() {
		for {
			c, acceptErr := ln.Accept()
			if acceptErr != nil {
				return
			}
			tcpConns.Add(1)
			_ = c.Close()
		}
	}()

	_, portStr, err := net.SplitHostPort(ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}

	cfgDir := t.TempDir()
	envContent := strings.Join([]string{
		"VPRO_PG_HOST=127.0.0.1",
		"VPRO_PG_PORT=" + portStr,
		"VPRO_PG_DBNAME=becmaster",
		"VPRO_PG_SSLMODE=disable",
		"VPRO_PG_USER=contrib",
		"VPRO_PG_PASSWORD=secret",
		"VPRO_PG_ADMIN_USER=custodian",
		"VPRO_PG_ADMIN_PASSWORD=secret",
	}, "\n")
	if err := os.WriteFile(filepath.Join(cfgDir, "becmaster.env"), []byte(envContent), 0o600); err != nil {
		t.Fatal(err)
	}

	t.Setenv("VPRO_CONFIG_DIR", cfgDir)
	t.Setenv("VPRO_RUN_LIVE_PG_TESTS", "")
	t.Setenv("VPRO_LIVE_PG_TEST", "")
	t.Setenv("VPRO_LIVE_PG", "")

	var subSkipped bool
	t.Run("unset_opt_in_skips", func(sub *testing.T) {
		defer func() {
			subSkipped = sub.Skipped()
		}()
		mgr := requireLivePostgresOrSkip(sub)
		mgr.Close()
	})
	if !subSkipped {
		t.Fatal("expected requireLivePostgresOrSkip to skip when opt-in env vars are unset")
	}
	if got := tcpConns.Load(); got != 0 {
		t.Fatalf("expected 0 TCP connections when live test opt-in is unset, got %d", got)
	}
}
