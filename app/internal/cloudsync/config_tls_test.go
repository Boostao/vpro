package cloudsync

import (
	"errors"
	"testing"
)

// UX-CLOUD-002: remote hosts must never accept an sslmode that allows plaintext.
func TestRemoteHostsRequireTLSForFieldAndURLCredentials(t *testing.T) {
	cases := []struct {
		name    string
		creds   ResolvedCredentials
		wantErr bool
	}{
		{"field remote disable", ResolvedCredentials{Host: "db.example.org", User: "u", UserPassword: "p", SSLMode: "disable"}, true},
		{"field remote allow", ResolvedCredentials{Host: "db.example.org", User: "u", UserPassword: "p", SSLMode: "allow"}, true},
		{"field remote prefer", ResolvedCredentials{Host: "db.example.org", User: "u", UserPassword: "p", SSLMode: "prefer"}, true},
		{"field remote ip disable", ResolvedCredentials{Host: "203.0.113.7", User: "u", UserPassword: "p", SSLMode: "disable"}, true},
		{"field remote require", ResolvedCredentials{Host: "db.example.org", User: "u", UserPassword: "p", SSLMode: "require"}, false},
		{"field remote default", ResolvedCredentials{Host: "db.example.org", User: "u", UserPassword: "p"}, false},
		{"field remote verify-full", ResolvedCredentials{Host: "db.example.org", User: "u", UserPassword: "p", SSLMode: "verify-full"}, false},
		{"field localhost disable", ResolvedCredentials{Host: "localhost", User: "u", UserPassword: "p", SSLMode: "disable"}, false},
		{"field 127.0.0.1 disable", ResolvedCredentials{Host: "127.0.0.1", User: "u", UserPassword: "p", SSLMode: "disable"}, false},
		{"field ::1 prefer", ResolvedCredentials{Host: "::1", User: "u", UserPassword: "p", SSLMode: "prefer"}, false},
		{"url remote disable", ResolvedCredentials{UserURL: "postgres://u:p@db.example.org:5432/becmaster?sslmode=disable"}, true},
		{"url remote prefer", ResolvedCredentials{UserURL: "postgres://u:p@db.example.org:5432/becmaster?sslmode=prefer"}, true},
		{"url remote require", ResolvedCredentials{UserURL: "postgres://u:p@db.example.org:5432/becmaster?sslmode=require"}, false},
		{"url loopback disable", ResolvedCredentials{UserURL: "postgres://u:p@127.0.0.1:5432/becmaster?sslmode=disable"}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			creds := tc.creds
			_, err := buildConnConfigForRole(&creds, RoleModeContributor)
			if tc.wantErr && !errors.Is(err, errRemotePlaintext) {
				t.Fatalf("want TLS-required error, got %v", err)
			}
			if !tc.wantErr && err != nil {
				t.Fatalf("want accepted, got %v", err)
			}
		})
	}
}

func TestPoolPathAlsoRejectsRemotePlaintext(t *testing.T) {
	m := NewManager(t.TempDir(), func(string) (string, bool) { return "", false })
	defer m.Close()
	if _, err := m.ConfigureSession(SessionConfigRequest{Host: "db.example.org", User: "u", Password: "p", SSLMode: "disable"}); err != nil {
		t.Fatal(err)
	}
	if _, _, err := m.AcquirePool(t.Context(), RoleModeContributor); !errors.Is(err, errRemotePlaintext) {
		t.Fatalf("pool path must reject remote plaintext before dialing, got %v", err)
	}
}
