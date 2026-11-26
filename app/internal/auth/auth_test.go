package auth

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type mockOIDCProvider struct {
	t            *testing.T
	server       *httptest.Server
	rsaKey       *rsa.PrivateKey
	ecKey        *ecdsa.PrivateKey
	activeAlg    string
	activeKid    string
	mu           sync.Mutex
	codes        map[string]mockAuthCode
	nextClaims   map[string]any
	accessClaims map[string]any
	refreshError string
	refreshCount atomic.Int32
	tokenHits    atomic.Int32
	jwksHits     atomic.Int32
	jwksKeys     []jwkKey
}

type mockAuthCode struct {
	challenge string
	nonce     string
	clientID  string
	redirect  string
}

func newMockOIDCProvider(t *testing.T, alg string) *mockOIDCProvider {
	t.Helper()
	rsaKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate RSA key: %v", err)
	}
	ecKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatalf("generate EC key: %v", err)
	}

	p := &mockOIDCProvider{
		t:         t,
		rsaKey:    rsaKey,
		ecKey:     ecKey,
		activeAlg: alg,
		activeKid: "kid-initial",
		codes:     make(map[string]mockAuthCode),
	}
	p.jwksKeys = p.buildDefaultJWKS()

	mux := http.NewServeMux()
	mux.HandleFunc("/.well-known/openid-configuration", p.handleDiscovery)
	mux.HandleFunc("/authorize", p.handleAuthorize)
	mux.HandleFunc("/token", p.handleToken)
	mux.HandleFunc("/jwks", p.handleJWKS)
	p.server = httptest.NewServer(mux)
	t.Cleanup(p.server.Close)
	return p
}

func (p *mockOIDCProvider) issuer() string {
	return p.server.URL
}

func (p *mockOIDCProvider) buildDefaultJWKS() []jwkKey {
	eBytes := big.NewInt(int64(p.rsaKey.PublicKey.E)).Bytes()
	rsaJWK := jwkKey{
		Kty: "RSA",
		Kid: "kid-initial",
		Use: "sig",
		N:   base64.RawURLEncoding.EncodeToString(p.rsaKey.PublicKey.N.Bytes()),
		E:   base64.RawURLEncoding.EncodeToString(eBytes),
	}
	ecJWK := jwkKey{
		Kty: "EC",
		Kid: "kid-ec-1",
		Use: "sig",
		Crv: "P-256",
		X:   base64.RawURLEncoding.EncodeToString(padBytes(p.ecKey.PublicKey.X.Bytes(), 32)),
		Y:   base64.RawURLEncoding.EncodeToString(padBytes(p.ecKey.PublicKey.Y.Bytes(), 32)),
	}
	return []jwkKey{rsaJWK, ecJWK}
}

func padBytes(b []byte, size int) []byte {
	if len(b) >= size {
		return b
	}
	out := make([]byte, size)
	copy(out[size-len(b):], b)
	return out
}

func (p *mockOIDCProvider) signJWT(claims map[string]any) string {
	p.t.Helper()
	p.mu.Lock()
	alg := p.activeAlg
	kid := p.activeKid
	p.mu.Unlock()

	header := map[string]any{"alg": alg, "typ": "JWT", "kid": kid}
	hJSON, _ := json.Marshal(header)
	cJSON, _ := json.Marshal(claims)
	signingInput := base64.RawURLEncoding.EncodeToString(hJSON) + "." + base64.RawURLEncoding.EncodeToString(cJSON)
	sum := sha256.Sum256([]byte(signingInput))

	var sig []byte
	var err error
	switch alg {
	case "RS256":
		sig, err = rsa.SignPKCS1v15(rand.Reader, p.rsaKey, crypto.SHA256, sum[:])
	case "PS256":
		sig, err = rsa.SignPSS(rand.Reader, p.rsaKey, crypto.SHA256, sum[:], &rsa.PSSOptions{SaltLength: rsa.PSSSaltLengthEqualsHash})
	case "ES256":
		r, s, signErr := ecdsa.Sign(rand.Reader, p.ecKey, sum[:])
		err = signErr
		if err == nil {
			sig = append(padBytes(r.Bytes(), 32), padBytes(s.Bytes(), 32)...)
		}
	default:
		p.t.Fatalf("unsupported mock alg %q", alg)
	}
	if err != nil {
		p.t.Fatalf("signJWT(%s): %v", alg, err)
	}
	return signingInput + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func (p *mockOIDCProvider) handleDiscovery(w http.ResponseWriter, r *http.Request) {
	_ = json.NewEncoder(w).Encode(oidcDiscoveryDoc{
		Issuer:                p.server.URL,
		AuthorizationEndpoint: p.server.URL + "/authorize",
		TokenEndpoint:         p.server.URL + "/token",
		JWKSURI:               p.server.URL + "/jwks",
	})
}

func (p *mockOIDCProvider) handleJWKS(w http.ResponseWriter, r *http.Request) {
	p.jwksHits.Add(1)
	p.mu.Lock()
	keys := append([]jwkKey(nil), p.jwksKeys...)
	p.mu.Unlock()
	_ = json.NewEncoder(w).Encode(jwkSet{Keys: keys})
}

func (p *mockOIDCProvider) handleAuthorize(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	if q.Get("code_challenge_method") != "S256" || q.Get("code_challenge") == "" {
		http.Error(w, "PKCE S256 required", http.StatusBadRequest)
		return
	}
	code := "mock-auth-code-123"
	p.mu.Lock()
	p.codes[code] = mockAuthCode{
		challenge: q.Get("code_challenge"),
		nonce:     q.Get("nonce"),
		clientID:  q.Get("client_id"),
		redirect:  q.Get("redirect_uri"),
	}
	p.mu.Unlock()

	cb, err := url.Parse(q.Get("redirect_uri"))
	if err != nil {
		http.Error(w, "bad redirect_uri", http.StatusBadRequest)
		return
	}
	cbQ := cb.Query()
	cbQ.Set("code", code)
	cbQ.Set("state", q.Get("state"))
	cb.RawQuery = cbQ.Encode()
	http.Redirect(w, r, cb.String(), http.StatusFound)
}

func (p *mockOIDCProvider) handleToken(w http.ResponseWriter, r *http.Request) {
	p.tokenHits.Add(1)
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad form", http.StatusBadRequest)
		return
	}
	grantType := r.FormValue("grant_type")
	switch grantType {
	case "authorization_code":
		code := r.FormValue("code")
		verifier := r.FormValue("code_verifier")
		p.mu.Lock()
		rec, ok := p.codes[code]
		customClaims := cloneMap(p.nextClaims)
		accessClaims := cloneMap(p.accessClaims)
		p.mu.Unlock()
		if !ok {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid_grant", "error_description": "unknown code"})
			return
		}
		sum := sha256.Sum256([]byte(verifier))
		expectedChallenge := base64.RawURLEncoding.EncodeToString(sum[:])
		if expectedChallenge != rec.challenge {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": "invalid_grant", "error_description": "PKCE verifier mismatch"})
			return
		}
		now := time.Now().UTC()
		claims := map[string]any{
			"iss":               p.server.URL,
			"sub":               "idir-sub-42",
			"aud":               rec.clientID,
			"exp":               now.Add(1 * time.Hour).Unix(),
			"iat":               now.Unix(),
			"nonce":             rec.nonce,
			"identity_provider": "idir",
			"idir_username":     "WMACKENZ",
			"name":              "Will MacKenzie",
			"email":             "will.mackenzie@gov.bc.ca",
			"client_roles":      []string{"vpro_custodian"},
		}
		for k, v := range customClaims {
			claims[k] = v
		}
		idToken := p.signJWT(claims)
		accessToken := "opaque-access-secret-token-xyz"
		if len(accessClaims) > 0 {
			accessClaims["iss"] = p.server.URL
			accessToken = p.signJWT(accessClaims)
		}
		_ = json.NewEncoder(w).Encode(oidcTokenResponse{
			AccessToken:  accessToken,
			RefreshToken: "refresh-secret-token-abc",
			IDToken:      idToken,
			TokenType:    "Bearer",
			ExpiresIn:    3600,
		})

	case "refresh_token":
		p.refreshCount.Add(1)
		p.mu.Lock()
		refErr := p.refreshError
		customClaims := cloneMap(p.nextClaims)
		p.mu.Unlock()
		if refErr != "" {
			w.WriteHeader(http.StatusBadRequest)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": refErr, "error_description": "token revoked"})
			return
		}
		now := time.Now().UTC()
		claims := map[string]any{
			"iss":               p.server.URL,
			"sub":               "idir-sub-42",
			"aud":               r.FormValue("client_id"),
			"exp":               now.Add(2 * time.Hour).Unix(),
			"iat":               now.Unix(),
			"identity_provider": "idir",
			"idir_username":     "WMACKENZ",
			"name":              "Will MacKenzie",
			"email":             "will.mackenzie@gov.bc.ca",
			"client_roles":      []string{"regional_ecologist"},
		}
		for k, v := range customClaims {
			claims[k] = v
		}
		_ = json.NewEncoder(w).Encode(oidcTokenResponse{
			AccessToken:  "refreshed-access-token-999",
			RefreshToken: "refreshed-refresh-token-888",
			IDToken:      p.signJWT(claims),
			TokenType:    "Bearer",
			ExpiresIn:    7200,
		})
	default:
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(map[string]string{"error": "unsupported_grant_type"})
	}
}

func cloneMap(in map[string]any) map[string]any {
	if in == nil {
		return nil
	}
	out := make(map[string]any, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}

func mapEnv(vals map[string]string) EnvLookup {
	return func(key string) (string, bool) {
		v, ok := vals[key]
		return v, ok
	}
}

func simulateBrowserRedirect(client *http.Client) BrowserOpener {
	return func(rawURL string) error {
		go func() {
			resp, err := client.Get(rawURL)
			if err == nil {
				_ = resp.Body.Close()
			}
		}()
		return nil
	}
}

func TestOIDCPKCEFlowRSAAndECDSAAndOfflineRestoreAndSilentRefresh(t *testing.T) {
	for _, tc := range []struct {
		name string
		alg  string
		kid  string
	}{
		{name: "RS256", alg: "RS256", kid: "kid-initial"},
		{name: "PS256", alg: "PS256", kid: "kid-initial"},
		{name: "ES256", alg: "ES256", kid: "kid-ec-1"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			prov := newMockOIDCProvider(t, tc.alg)
			prov.activeKid = tc.kid
			cfgDir := t.TempDir()

			env := mapEnv(map[string]string{
				"VPRO_OIDC_ISSUER":    prov.issuer(),
				"VPRO_OIDC_CLIENT_ID": "vpro-desktop-client",
			})
			mgr := NewManager(cfgDir, env,
				WithHTTPClient(prov.server.Client()),
				WithBrowserOpener(simulateBrowserRedirect(prov.server.Client())),
			)

			if !mgr.OIDCConfigured() {
				t.Fatal("expected OIDCConfigured=true")
			}
			if mgr.DevFallbackAvailable() {
				t.Fatal("expected DevFallbackAvailable=false when OIDC client ID is configured")
			}

			res, err := mgr.BeginOIDCSignIn(context.Background(), "idir")
			if err != nil {
				t.Fatalf("BeginOIDCSignIn(%s) failed: %v", tc.alg, err)
			}
			if !res.Completed || !res.BrowserOpened || !res.Session.SignedIn {
				t.Fatalf("unexpected SignInResult: %+v", res)
			}
			if !strings.Contains(res.AuthURL, "code_challenge_method=S256") || !strings.Contains(res.AuthURL, "kc_idp_hint=idir") {
				t.Fatalf("AuthURL missing PKCE S256 or kc_idp_hint: %s", res.AuthURL)
			}
			if res.Session.UserID != "WMACKENZ" || res.Session.DisplayName != "Will MacKenzie" ||
				res.Session.Role != RoleCustodian || res.Session.IdentityProvider != "idir" ||
				!res.Session.CanEditBECMaster || !res.Session.CanEditWorkingProjects {
				t.Fatalf("unexpected mapped BC Gov session: %+v", res.Session)
			}

			// Verify persisted session file permissions are strictly 0600.
			sessionPath := filepath.Join(cfgDir, authSessionFileName)
			info, err := os.Stat(sessionPath)
			if err != nil {
				t.Fatalf("stat auth_session.json: %v", err)
			}
			if perm := info.Mode().Perm(); perm != 0o600 {
				t.Fatalf("auth_session.json perm = %#o, want 0600", perm)
			}
		})
	}

	t.Run("OfflineRestoreAndOnlineSilentRefreshAndRevocation", func(t *testing.T) {
		prov := newMockOIDCProvider(t, "RS256")
		cfgDir := t.TempDir()
		now := time.Now().UTC()

		env := mapEnv(map[string]string{
			"VPRO_OIDC_ISSUER":    prov.issuer(),
			"VPRO_OIDC_CLIENT_ID": "vpro-desktop-client",
		})
		mgr := NewManager(cfgDir, env,
			WithHTTPClient(prov.server.Client()),
			WithBrowserOpener(simulateBrowserRedirect(prov.server.Client())),
			WithClock(func() time.Time { return now }),
		)
		if _, err := mgr.BeginOIDCSignIn(context.Background(), "idir"); err != nil {
			t.Fatalf("initial sign-in failed: %v", err)
		}

		// 1. Fresh Manager instance restores cached session while token is expired and IdP is unreachable (offline).
		offlineEnv := mapEnv(map[string]string{
			"VPRO_OIDC_ISSUER":    "http://127.0.0.1:1", // unreachable loopback
			"VPRO_OIDC_CLIENT_ID": "vpro-desktop-client",
		})
		// Rewrite issuer in stored session or point manager at unreachable client.
		failingClient := &http.Client{
			Transport: roundTripFunc(func(*http.Request) (*http.Response, error) {
				return nil, errors.New("network unreachable (offline)")
			}),
		}
		offlineMgr := NewManager(cfgDir, env,
			WithHTTPClient(failingClient),
			WithClock(func() time.Time { return now.Add(2 * time.Hour) }), // past 1h token expiry
		)
		_ = offlineEnv
		offlineSummary, err := offlineMgr.GetSession(context.Background())
		if err != nil {
			t.Fatalf("offline GetSession failed: %v", err)
		}
		if !offlineSummary.SignedIn || !offlineSummary.OfflineMode || offlineSummary.Role != RoleCustodian || offlineSummary.UserID != "WMACKENZ" {
			t.Fatalf("expected offline cached custodian session, got %+v", offlineSummary)
		}

		// 2. When back online past token expiry, silent refresh updates role claim (mock returns regional_ecologist).
		onlineMgr := NewManager(cfgDir, env,
			WithHTTPClient(prov.server.Client()),
			WithClock(func() time.Time { return now.Add(2 * time.Hour) }),
		)
		refreshed, err := onlineMgr.GetSession(context.Background())
		if err != nil {
			t.Fatalf("online silent refresh failed: %v", err)
		}
		if !refreshed.SignedIn || refreshed.OfflineMode || refreshed.Role != RoleRegionalEcologist || prov.refreshCount.Load() != 1 {
			t.Fatalf("expected silent refresh to update role to regional_ecologist: %+v refreshCount=%d", refreshed, prov.refreshCount.Load())
		}

		// 3. When IdP explicitly revokes refresh token with invalid_grant, cached session is cleared!
		prov.mu.Lock()
		prov.refreshError = "invalid_grant"
		prov.mu.Unlock()
		revokedMgr := NewManager(cfgDir, env,
			WithHTTPClient(prov.server.Client()),
			WithClock(func() time.Time { return now.Add(10 * time.Hour) }),
		)
		revokedSummary, err := revokedMgr.GetSession(context.Background())
		if err != nil {
			t.Fatalf("revoked GetSession returned unexpected error: %v", err)
		}
		if revokedSummary.SignedIn || revokedSummary.UserID != "" || revokedSummary.Role != "" {
			t.Fatalf("expected revoked session to clear SignedIn, got %+v", revokedSummary)
		}
	})
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) {
	return f(r)
}

func TestJWTValidationRejectsInvalidAlgIssAudExpNonceAndSupportsJWKSKeyRotation(t *testing.T) {
	prov := newMockOIDCProvider(t, "RS256")
	cfgDir := t.TempDir()
	env := mapEnv(map[string]string{
		"VPRO_OIDC_ISSUER":    prov.issuer(),
		"VPRO_OIDC_CLIENT_ID": "vpro-client",
	})
	mgr := NewManager(cfgDir, env, WithHTTPClient(prov.server.Client()))
	doc, err := mgr.fetchDiscovery(context.Background(), prov.issuer())
	if err != nil {
		t.Fatalf("fetchDiscovery: %v", err)
	}
	cfg := mgr.ResolveOIDCConfig()

	// Reject alg=none attack
	noneHdr := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"none","typ":"JWT"}`))
	nonePay := base64.RawURLEncoding.EncodeToString([]byte(`{"iss":"` + prov.issuer() + `","sub":"x","aud":"vpro-client","exp":9999999999}`))
	if _, err := mgr.verifyJWTWithJWKS(context.Background(), doc.JWKSURI, noneHdr+"."+nonePay+"."); err == nil {
		t.Fatal("expected alg=none JWT to be rejected")
	}

	// Reject HS256 alg confusion attack
	hsHdr := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	if _, err := mgr.verifyJWTWithJWKS(context.Background(), doc.JWKSURI, hsHdr+"."+nonePay+".AAAA"); err == nil {
		t.Fatal("expected HS256 JWT to be rejected")
	}

	baseClaims := func() map[string]any {
		now := time.Now().UTC()
		return map[string]any{
			"iss":   prov.issuer(),
			"sub":   "user-1",
			"aud":   "vpro-client",
			"exp":   now.Add(10 * time.Minute).Unix(),
			"iat":   now.Unix(),
			"nonce": "expected-nonce",
		}
	}

	// Bad issuer
	badIss := baseClaims()
	badIss["iss"] = "https://evil.example.com"
	if _, err := mgr.verifyAndExtractIdentity(context.Background(), doc, cfg, oidcTokenResponse{IDToken: prov.signJWT(badIss)}, "expected-nonce"); err == nil {
		t.Fatal("expected issuer mismatch to fail")
	}

	// Bad audience
	badAud := baseClaims()
	badAud["aud"] = "other-client"
	if _, err := mgr.verifyAndExtractIdentity(context.Background(), doc, cfg, oidcTokenResponse{IDToken: prov.signJWT(badAud)}, "expected-nonce"); err == nil {
		t.Fatal("expected audience mismatch to fail")
	}

	// Expired token
	expired := baseClaims()
	expired["exp"] = time.Now().UTC().Add(-5 * time.Minute).Unix()
	if _, err := mgr.verifyAndExtractIdentity(context.Background(), doc, cfg, oidcTokenResponse{IDToken: prov.signJWT(expired)}, "expected-nonce"); err == nil {
		t.Fatal("expected expired JWT to fail")
	}

	// Wrong nonce
	if _, err := mgr.verifyAndExtractIdentity(context.Background(), doc, cfg, oidcTokenResponse{IDToken: prov.signJWT(baseClaims())}, "different-nonce"); err == nil {
		t.Fatal("expected nonce mismatch to fail")
	}

	// Tampered payload fails RSA signature check
	goodJWT := prov.signJWT(baseClaims())
	parts := strings.Split(goodJWT, ".")
	tamperedPay := base64.RawURLEncoding.EncodeToString([]byte(`{"iss":"` + prov.issuer() + `","sub":"admin","aud":"vpro-client","exp":9999999999,"nonce":"expected-nonce","client_roles":["custodian"]}`))
	if _, err := mgr.verifyJWTWithJWKS(context.Background(), doc.JWKSURI, parts[0]+"."+tamperedPay+"."+parts[2]); err == nil {
		t.Fatal("expected tampered JWT payload to fail signature verification")
	}

	// Key rotation: introduce a brand-new kid into JWKS after initial cache fill
	rotatedKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	prov.mu.Lock()
	prov.rsaKey = rotatedKey
	prov.activeKid = "kid-rotated-2"
	prov.jwksKeys = append(prov.jwksKeys, jwkKey{
		Kty: "RSA",
		Kid: "kid-rotated-2",
		Use: "sig",
		N:   base64.RawURLEncoding.EncodeToString(rotatedKey.PublicKey.N.Bytes()),
		E:   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(rotatedKey.PublicKey.E)).Bytes()),
	})
	prov.mu.Unlock()
	if _, err := mgr.verifyAndExtractIdentity(context.Background(), doc, cfg, oidcTokenResponse{IDToken: prov.signJWT(baseClaims())}, "expected-nonce"); err != nil {
		t.Fatalf("expected JWKS key rotation refresh to succeed, got: %v", err)
	}
}

func TestBCGovClaimMappingAndRolePrecedence(t *testing.T) {
	if got := MapBCGovRoles(nil); got != RoleViewer {
		t.Fatalf("empty roles mapped to %q, want %q", got, RoleViewer)
	}
	if got := MapBCGovRoles([]string{"unknown_role"}); got != RoleViewer {
		t.Fatalf("unknown role mapped to %q, want %q", got, RoleViewer)
	}
	if got := MapBCGovRoles([]string{"viewer", "vpro_contributor"}); got != RoleContributor {
		t.Fatalf("contributor role mapped to %q, want %q", got, RoleContributor)
	}
	if got := MapBCGovRoles([]string{"contributor", "bec-regional-ecologist"}); got != RoleRegionalEcologist {
		t.Fatalf("regional ecologist role mapped to %q, want %q", got, RoleRegionalEcologist)
	}
	if got := MapBCGovRoles([]string{"regional_ecologist", "becmaster_custodian"}); got != RoleCustodian {
		t.Fatalf("custodian role mapped to %q, want %q", got, RoleCustodian)
	}

	// BCeID user with roles carried in verified JWT access_token
	prov := newMockOIDCProvider(t, "RS256")
	prov.mu.Lock()
	prov.nextClaims = map[string]any{
		"identity_provider": "bceidbusiness",
		"idir_username":     "",
		"bceid_username":    "jdoe_consultant",
		"name":              "Jane Doe",
		"email":             "jane.doe@consultants.bc.ca",
		"client_roles":      []string{},
	}
	prov.accessClaims = map[string]any{
		"client_roles": []string{"vpro_contributor"},
	}
	prov.mu.Unlock()

	mgr := NewManager(t.TempDir(), mapEnv(map[string]string{
		"VPRO_OIDC_ISSUER":    prov.issuer(),
		"VPRO_OIDC_CLIENT_ID": "vpro-desktop",
	}), WithHTTPClient(prov.server.Client()), WithBrowserOpener(simulateBrowserRedirect(prov.server.Client())))

	res, err := mgr.BeginOIDCSignIn(context.Background(), "bceidbusiness")
	if err != nil {
		t.Fatalf("BCeID sign-in failed: %v", err)
	}
	if res.Session.UserID != "jdoe_consultant" || res.Session.IdentityProvider != "bceidbusiness" || res.Session.Role != RoleContributor || res.Session.CanEditBECMaster || !res.Session.CanEditWorkingProjects {
		t.Fatalf("unexpected BCeID session: %+v", res.Session)
	}
}

func TestDevEvaluationFallbackGatingAndSignOut(t *testing.T) {
	cfgDir := t.TempDir()
	mgr := NewManager(cfgDir, mapEnv(map[string]string{}))
	if mgr.OIDCConfigured() {
		t.Fatal("expected OIDCConfigured=false with empty env")
	}
	if compiledProductionBuild {
		if mgr.DevFallbackAvailable() {
			t.Fatal("expected DevFallbackAvailable=false in production-tagged build")
		}
		if _, err := mgr.CompleteDevEvaluationSignIn(context.Background(), "dev.ecologist", "Dev Ecologist", RoleRegionalEcologist); !errors.Is(err, ErrDevFallbackDisabled) {
			t.Fatalf("expected ErrDevFallbackDisabled in production-tagged build, got %v", err)
		}
		return
	}
	if !mgr.DevFallbackAvailable() {
		t.Fatal("expected DevFallbackAvailable=true in dev build with unconfigured OIDC")
	}

	sess, err := mgr.CompleteDevEvaluationSignIn(context.Background(), "dev.ecologist", "Dev Ecologist", RoleRegionalEcologist)
	if err != nil {
		t.Fatalf("CompleteDevEvaluationSignIn failed: %v", err)
	}
	if !sess.SignedIn || !sess.IsDevEvaluation || sess.Role != RoleRegionalEcologist || sess.IdentityProvider != "dev_evaluation" {
		t.Fatalf("unexpected dev session: %+v", sess)
	}

	// Reloading in release mode or with OIDC configured must NEVER honor a persisted dev evaluation session.
	releaseMgr := NewManager(cfgDir, mapEnv(map[string]string{"VPRO_BUILD_MODE": "release"}))
	if releaseMgr.DevFallbackAvailable() {
		t.Fatal("expected DevFallbackAvailable=false in release mode")
	}
	if _, err := releaseMgr.CompleteDevEvaluationSignIn(context.Background(), "x", "X", RoleCustodian); !errors.Is(err, ErrDevFallbackDisabled) {
		t.Fatalf("expected ErrDevFallbackDisabled in release mode, got %v", err)
	}
	reloadedRelease, err := releaseMgr.GetSession(context.Background())
	if err != nil || reloadedRelease.SignedIn {
		t.Fatalf("persisted dev session must be ignored in release mode: %+v err=%v", reloadedRelease, err)
	}

	// Configured OIDC also disables dev fallback.
	oidcMgr := NewManager(cfgDir, mapEnv(map[string]string{"VPRO_OIDC_CLIENT_ID": "real-client"}))
	if _, err := oidcMgr.CompleteDevEvaluationSignIn(context.Background(), "x", "X", RoleCustodian); !errors.Is(err, ErrDevFallbackDisabled) {
		t.Fatalf("expected ErrDevFallbackDisabled when OIDC is configured, got %v", err)
	}

	// SignOut clears persisted session while preserving MachineID.
	signedOut, err := mgr.SignOut(context.Background())
	if err != nil {
		t.Fatalf("SignOut failed: %v", err)
	}
	if signedOut.SignedIn || signedOut.UserID != "" || signedOut.MachineID != sess.MachineID {
		t.Fatalf("unexpected SignOut summary: %+v (prev machineId=%s)", signedOut, sess.MachineID)
	}
}

func TestSecretRedaction(t *testing.T) {
	raw := "failed calling https://loginproxy.gov.bc.ca with Bearer super-secret-bearer and access_token=tok12345 refresh_token=ref98765 jwt eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTYifQ.sigvalue12345 and postgres://u:pw@host:5432/db"
	redacted := RedactAuthSecrets(raw, "customSecretValue")
	for _, leaked := range []string{"super-secret-bearer", "tok12345", "ref98765", "sigvalue12345", "u:pw@host"} {
		if strings.Contains(redacted, leaked) {
			t.Fatalf("RedactAuthSecrets leaked %q in %q", leaked, redacted)
		}
	}
}

func TestTelemetryOfflineQueueAndHTTPAndPostgresFlush(t *testing.T) {
	cfgDir := t.TempDir()

	// 1. Offline mode (no endpoints configured): events enqueue locally and enrollment deduplicates per version.
	offlineMgr := NewManager(cfgDir, mapEnv(map[string]string{}), WithAppVersion("2.0.0-alpha.1"))
	enroll1, err := offlineMgr.EnsureMachineEnrollment(context.Background(), "2.0.0-alpha.1")
	if err != nil || !enroll1.Queued || enroll1.Deduplicated || enroll1.PendingCount != 1 {
		t.Fatalf("first EnsureMachineEnrollment unexpected: %+v err=%v", enroll1, err)
	}
	enroll2, err := offlineMgr.EnsureMachineEnrollment(context.Background(), "2.0.0-alpha.1")
	if err != nil || enroll2.Queued || !enroll2.Deduplicated || enroll2.PendingCount != 1 {
		t.Fatalf("duplicate EnsureMachineEnrollment unexpected: %+v err=%v", enroll2, err)
	}
	// Version bump re-enrolls once.
	enroll3, err := offlineMgr.EnsureMachineEnrollment(context.Background(), "2.0.0-alpha.2")
	if err != nil || !enroll3.Queued || enroll3.PendingCount != 2 {
		t.Fatalf("version-bump EnsureMachineEnrollment unexpected: %+v err=%v", enroll3, err)
	}
	uploadRec, err := offlineMgr.RecordActivity(context.Background(), EventKindDatasetUpload, "Haida_Gwaii_2019", 142)
	if err != nil || !uploadRec.Queued || uploadRec.PendingCount != 3 {
		t.Fatalf("RecordActivity upload unexpected: %+v err=%v", uploadRec, err)
	}

	// Verify 0600 permissions on activity_queue.json
	info, err := os.Stat(filepath.Join(cfgDir, activityQueueFileName))
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("activity_queue.json perm=%v err=%v", info, err)
	}

	// 2. Online HTTP endpoint flushes queued events cleanly.
	var received []ActivityEvent
	var authHeader string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader = r.Header.Get("Authorization")
		var payload struct {
			Events []ActivityEvent `json:"events"`
		}
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			http.Error(w, "bad json", http.StatusBadRequest)
			return
		}
		received = append(received, payload.Events...)
		w.WriteHeader(http.StatusAccepted)
	}))
	defer srv.Close()

	httpMgr := NewManager(cfgDir, mapEnv(map[string]string{
		"VPRO_TELEMETRY_URL":   srv.URL + "/events",
		"VPRO_TELEMETRY_TOKEN": "telemetry-secret-key",
	}), WithHTTPClient(srv.Client()))

	flushed, err := httpMgr.FlushTelemetry(context.Background())
	if err != nil || flushed != 3 || len(received) != 3 || authHeader != "Bearer telemetry-secret-key" {
		t.Fatalf("HTTP FlushTelemetry failed: flushed=%d len=%d auth=%q err=%v", flushed, len(received), authHeader, err)
	}
	if httpMgr.PendingActivityCount() != 0 {
		t.Fatalf("expected 0 pending events after flush, got %d", httpMgr.PendingActivityCount())
	}

	// 3. Postgres download_log sink fallback delivers queued events.
	var pgMu sync.Mutex
	var pgEvents []ActivityEvent
	pgMgr := NewManager(cfgDir, mapEnv(map[string]string{}), WithPGActivitySink(func(ctx context.Context, evt ActivityEvent) error {
		pgMu.Lock()
		pgEvents = append(pgEvents, evt)
		pgMu.Unlock()
		return nil
	}))
	if _, err := pgMgr.RecordActivity(context.Background(), EventKindDatasetDownload, "BECMaster_Skeena", 512); err != nil {
		t.Fatalf("RecordActivity download failed: %v", err)
	}
	// Synchronous flush serializes with any background async flush via flushMu.
	if _, err := pgMgr.FlushTelemetry(context.Background()); err != nil {
		t.Fatalf("PG FlushTelemetry failed: %v", err)
	}
	pgMu.Lock()
	pgLen := len(pgEvents)
	var firstPlotCount int
	if pgLen > 0 {
		firstPlotCount = pgEvents[0].PlotCount
	}
	pgMu.Unlock()
	if pgMgr.PendingActivityCount() != 0 || pgLen != 1 || firstPlotCount != 512 {
		t.Fatalf("PG telemetry sink did not flush exactly once: pending=%d len=%d plotCount=%d", pgMgr.PendingActivityCount(), pgLen, firstPlotCount)
	}

	// 4. Reject non-HTTPS remote URLs cleanly.
	if err := requireHTTPSOrLoopback("http://telemetry.example.gov.bc.ca/events"); err == nil {
		t.Fatal("expected non-HTTPS remote telemetry URL to be rejected")
	}
}
