package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/resources"
)

const maxRPCRequestBodyBytes = 16 * 1024 * 1024 // 16 MiB

// WebRPCAllowlist matches app/resources/web_rpc_allowlist.json.
type WebRPCAllowlist struct {
	Version     int                          `json:"version"`
	Description string                       `json:"description"`
	Kinds       map[string]string            `json:"kinds"`
	Services    map[string]map[string]string `json:"services"`
}

func LoadWebRPCAllowlist() (WebRPCAllowlist, error) {
	var al WebRPCAllowlist
	dec := json.NewDecoder(bytes.NewReader(resources.WebRPCAllowlistJSON))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&al); err != nil {
		return WebRPCAllowlist{}, fmt.Errorf("decode web_rpc_allowlist.json: %w", err)
	}
	if al.Version != 1 || len(al.Services) == 0 {
		return WebRPCAllowlist{}, errors.New("invalid web_rpc_allowlist.json")
	}
	return al, nil
}

type rpcVoid struct{}

var voidResult = rpcVoid{}

type downloadResult struct {
	Outcome     any    `json:"outcome"`
	DownloadURL string `json:"downloadUrl"`
	Filename    string `json:"filename"`
}

type rpcError struct {
	status     int
	message    string
	retryAfter int
}

func (e *rpcError) Error() string { return e.message }

func errBadRequest(format string, args ...any) error {
	return &rpcError{status: http.StatusBadRequest, message: fmt.Sprintf(format, args...)}
}

func errForbidden(format string, args ...any) error {
	return &rpcError{status: http.StatusForbidden, message: fmt.Sprintf(format, args...)}
}

func errConflict(format string, args ...any) error {
	return &rpcError{status: http.StatusConflict, message: fmt.Sprintf(format, args...)}
}

func errServiceUnavailable(msg string, retryAfter int) error {
	return &rpcError{status: http.StatusServiceUnavailable, message: msg, retryAfter: retryAfter}
}

type rpcCall struct {
	ctx     context.Context
	server  *WebServer
	session *WebSession
	service string
	method  string
	kind    string
	args    []json.RawMessage
}

type rpcHandlerFunc func(c *rpcCall) (any, error)

type registeredRPC struct {
	service   string
	method    string
	kind      string
	cacheable bool
	fn        rpcHandlerFunc
}

type RPCRouter struct {
	server    *WebServer
	allowlist WebRPCAllowlist
	handlers  map[string]registeredRPC // "Service.Method" -> entry
}

func NewRPCRouter(server *WebServer) (*RPCRouter, error) {
	allowlist, err := LoadWebRPCAllowlist()
	if err != nil {
		return nil, err
	}
	r := &RPCRouter{
		server:    server,
		allowlist: allowlist,
		handlers:  make(map[string]registeredRPC, 300),
	}

	r.registerContextHandlers()
	r.registerPlotEntryHandlers()
	r.registerClassificationHandlers()
	r.registerVegReportHandlers()
	r.registerEnvReportHandlers()
	r.registerSpatialHandlers()
	r.registerImportExportHandlers()
	r.registerMiscHandlers()

	// Strict startup bijection check:
	// 1) Every allowlisted Service.Method MUST have a registered handler.
	// 2) No handler may be registered unless present in web_rpc_allowlist.json.
	var missing []string
	allowedSet := make(map[string]string, 300)
	for svc, methods := range allowlist.Services {
		for method, kind := range methods {
			key := svc + "." + method
			allowedSet[key] = kind
			reg, ok := r.handlers[key]
			if !ok {
				missing = append(missing, key)
				continue
			}
			if reg.kind != kind {
				return nil, fmt.Errorf("RPC %s kind mismatch: allowlist=%q handler=%q", key, kind, reg.kind)
			}
		}
	}
	if len(missing) > 0 {
		return nil, fmt.Errorf("RPC router missing %d allowlisted handlers (first: %s)", len(missing), missing[0])
	}
	for key := range r.handlers {
		if _, ok := allowedSet[key]; !ok {
			return nil, fmt.Errorf("RPC router registered non-allowlisted method %s", key)
		}
	}
	return r, nil
}

func (r *RPCRouter) register(service, method, kind string, cacheable bool, fn rpcHandlerFunc) {
	key := service + "." + method
	if _, dup := r.handlers[key]; dup {
		panic("duplicate RPC handler registration: " + key)
	}
	if kind != "rpc" {
		cacheable = false
	}
	r.handlers[key] = registeredRPC{
		service:   service,
		method:    method,
		kind:      kind,
		cacheable: cacheable,
		fn:        fn,
	}
}

func (r *RPCRouter) RegisteredCount() int {
	return len(r.handlers)
}

func (r *RPCRouter) HasHandler(service, method string) bool {
	_, ok := r.handlers[service+"."+method]
	return ok
}

type rpcRequestEnvelope struct {
	Args []json.RawMessage `json:"args"`
}

func (r *RPCRouter) ServeHTTP(w http.ResponseWriter, req *http.Request) {
	if req.Method != http.MethodPost {
		w.Header().Set("Allow", "POST")
		writeJSONError(w, http.StatusMethodNotAllowed, "RPC endpoints require POST")
		return
	}

	rel := strings.TrimPrefix(req.URL.Path, "/api/rpc/")
	parts := strings.Split(rel, "/")
	if len(parts) != 2 || strings.TrimSpace(parts[0]) == "" || strings.TrimSpace(parts[1]) == "" {
		writeJSONError(w, http.StatusBadRequest, "expected /api/rpc/{service}/{method}")
		return
	}
	service, method := parts[0], parts[1]
	key := service + "." + method

	entry, allowed := r.handlers[key]
	if !allowed {
		writeJSONError(w, http.StatusForbidden, fmt.Sprintf("RPC %s is not permitted in VPro web read-only mode", key))
		return
	}

	limited := io.LimitReader(req.Body, maxRPCRequestBodyBytes+1)
	rawBody, err := io.ReadAll(limited)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "failed to read request body")
		return
	}
	if len(rawBody) > maxRPCRequestBodyBytes {
		writeJSONError(w, http.StatusRequestEntityTooLarge, "request body exceeds maximum allowed size")
		return
	}

	var envelope rpcRequestEnvelope
	if len(bytes.TrimSpace(rawBody)) > 0 {
		dec := json.NewDecoder(bytes.NewReader(rawBody))
		dec.DisallowUnknownFields()
		if err := dec.Decode(&envelope); err != nil {
			writeJSONError(w, http.StatusBadRequest, fmt.Sprintf("invalid RPC request envelope: %v", err))
			return
		}
		if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
			writeJSONError(w, http.StatusBadRequest, "unexpected trailing JSON data in RPC request")
			return
		}
	}

	session, err := r.server.sessions.GetOrCreate(req.Header.Get("X-VPro-Session"))
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("initialize session: %v", err))
		return
	}

	var cacheKey string
	if entry.cacheable {
		gen := r.server.pool.Generation()
		cacheKey = BuildPreviewCacheKey(gen, service, method, envelope.Args)
		if cachedBody, etag, ok := r.server.cache.Get(cacheKey); ok {
			w.Header().Set("ETag", etag)
			w.Header().Set("X-VPro-Cache", "HIT")
			if etagMatches(req.Header.Get("If-None-Match"), etag) {
				w.WriteHeader(http.StatusNotModified)
				return
			}
			w.Header().Set("Content-Type", "application/json; charset=utf-8")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(cachedBody)
			return
		}
	}

	call := &rpcCall{
		ctx:     req.Context(),
		server:  r.server,
		session: session,
		service: service,
		method:  method,
		kind:    entry.kind,
		args:    envelope.Args,
	}

	result, err := entry.fn(call)
	if err != nil {
		r.writeRPCError(w, err)
		return
	}

	if _, isVoid := result.(rpcVoid); isVoid {
		w.WriteHeader(http.StatusNoContent)
		return
	}

	if entry.kind == "download" {
		dl, ok := result.(*downloadResult)
		if !ok || dl == nil {
			writeJSONError(w, http.StatusInternalServerError, "download handler returned invalid payload")
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		writeJSON(w, http.StatusOK, dl)
		return
	}

	encoded, err := json.Marshal(struct {
		Result any `json:"result"`
	}{Result: result})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, fmt.Sprintf("encode RPC response: %v", err))
		return
	}

	if entry.cacheable && cacheKey != "" {
		etag := r.server.cache.Set(cacheKey, encoded)
		w.Header().Set("ETag", etag)
		w.Header().Set("X-VPro-Cache", "MISS")
		if etagMatches(req.Header.Get("If-None-Match"), etag) {
			w.WriteHeader(http.StatusNotModified)
			return
		}
	}

	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(encoded)
}

func (r *RPCRouter) writeRPCError(w http.ResponseWriter, err error) {
	var re *rpcError
	if errors.As(err, &re) {
		if re.retryAfter > 0 {
			w.Header().Set("Retry-After", fmt.Sprintf("%d", re.retryAfter))
		}
		writeJSONError(w, re.status, re.message)
		return
	}
	switch {
	case errors.Is(err, vprocore.ErrStaleWebContext):
		writeJSONError(w, http.StatusConflict, err.Error())
	case errors.Is(err, vprocore.ErrUnknownDataset):
		writeJSONError(w, http.StatusBadRequest, err.Error())
	case errors.Is(err, vprocore.ErrReadOnlyContext):
		writeJSONError(w, http.StatusForbidden, "database writes are disabled in VPro web read-only mode")
	case errors.Is(err, context.Canceled):
		writeJSONError(w, 499, "request canceled")
	case errors.Is(err, context.DeadlineExceeded):
		writeJSONError(w, http.StatusGatewayTimeout, "request timed out")
	default:
		writeJSONError(w, http.StatusBadRequest, err.Error())
	}
}

// --- Typed argument decoding & lease/semaphore helpers ---

func (c *rpcCall) requireArgCount(n int) error {
	if len(c.args) != n {
		return errBadRequest("%s.%s expects %d argument(s), got %d", c.service, c.method, n, len(c.args))
	}
	return nil
}

func decodeArg[T any](c *rpcCall, index int) (T, error) {
	var zero T
	if index < 0 || index >= len(c.args) {
		return zero, errBadRequest("%s.%s missing argument %d", c.service, c.method, index)
	}
	var out T
	if err := json.Unmarshal(c.args[index], &out); err != nil {
		return zero, errBadRequest("%s.%s invalid argument %d: %v", c.service, c.method, index, err)
	}
	return out, nil
}

func (c *rpcCall) acquireByContextID(contextID string) (*vprocore.ReadOnlyLease, error) {
	if strings.TrimSpace(contextID) == "" {
		return nil, errBadRequest("%s.%s requires a non-empty contextID", c.service, c.method)
	}
	lease, err := c.server.pool.AcquireByContextID(c.ctx, contextID, c.session.Prefs)
	if err != nil {
		return nil, err
	}
	return lease, nil
}

func (c *rpcCall) acquireSessionLease() (*vprocore.ReadOnlyLease, *LoadedSnapshot, error) {
	snap := c.server.currentSnapshot()
	if snap == nil {
		return nil, nil, errServiceUnavailable("snapshot catalog is unavailable", 5)
	}
	sel, ok := c.session.Selection()
	if !ok {
		sel = snap.DefaultSelection()
	} else {
		if _, found := snap.FindDataset(sel.DatasetID, ""); !found {
			sel = snap.DefaultSelection()
			c.session.SetSelection(sel)
		}
	}
	lease, err := c.server.pool.Acquire(c.ctx, sel, c.session.Prefs)
	if err != nil {
		return nil, nil, err
	}
	return lease, snap, nil
}

// withExportSlot enforces VPRO_WEB_EXPORT_CONCURRENCY & VPRO_WEB_EXPORT_TIMEOUT,
// returning 503 Service Unavailable + Retry-After: 5 if the export queue is full.
func (c *rpcCall) withExportSlot(fn func(ctx context.Context) (*downloadResult, error)) (*downloadResult, error) {
	timeoutCtx, cancel := context.WithTimeout(c.ctx, c.server.cfg.ExportTimeout)
	defer cancel()

	select {
	case c.server.exportSem <- struct{}{}:
	case <-timeoutCtx.Done():
		if errors.Is(c.ctx.Err(), context.Canceled) {
			return nil, context.Canceled
		}
		return nil, errServiceUnavailable("export worker pool is busy; please retry shortly", 5)
	}
	c.server.exportInFlight.Add(1)
	defer func() {
		c.server.exportInFlight.Add(-1)
		<-c.server.exportSem
	}()

	return fn(timeoutCtx)
}

// withRSlot enforces VPRO_WEB_R_CONCURRENCY & VPRO_WEB_R_TIMEOUT,
// returning 503 Service Unavailable + Retry-After: 5 if the R sidecar queue is full.
func (c *rpcCall) withRSlot(fn func(ctx context.Context) (any, error)) (any, error) {
	timeoutCtx, cancel := context.WithTimeout(c.ctx, c.server.cfg.RTimeout)
	defer cancel()

	select {
	case c.server.rSem <- struct{}{}:
	case <-timeoutCtx.Done():
		if errors.Is(c.ctx.Err(), context.Canceled) {
			return nil, context.Canceled
		}
		return nil, errServiceUnavailable("R analytical worker pool is busy; please retry shortly", 5)
	}
	c.server.rInFlight.Add(1)
	defer func() {
		c.server.rInFlight.Add(-1)
		<-c.server.rSem
	}()

	return fn(timeoutCtx)
}

// rewriteJSONField parses rawJSON as a JSON object (preserving exact numbers) and
// unconditionally overrides key with value so client-supplied filesystem paths are ignored.
func rewriteJSONField(rawJSON, key, value string) (string, error) {
	dec := json.NewDecoder(strings.NewReader(rawJSON))
	dec.UseNumber()
	var obj map[string]any
	if err := dec.Decode(&obj); err != nil {
		return "", errBadRequest("invalid JSON request object: %v", err)
	}
	if obj == nil {
		obj = map[string]any{}
	}
	obj[key] = value
	encoded, err := json.Marshal(obj)
	if err != nil {
		return "", fmt.Errorf("re-encode JSON request: %w", err)
	}
	return string(encoded), nil
}

// guardSnapshotDBPath rejects client-supplied external filesystem DB paths that do not
// belong to the active verified snapshot bundle.
func (c *rpcCall) guardSnapshotDBPath(rawPath, fieldName string) error {
	trimmed := strings.TrimSpace(rawPath)
	if trimmed == "" {
		return nil
	}
	snap := c.server.currentSnapshot()
	if snap == nil || !snap.IsAllowedDBPath(trimmed) {
		return errForbidden("external filesystem path %q is not permitted for %s in web read-only mode", trimmed, fieldName)
	}
	return nil
}

// marshalTypedJSON mirrors app/domainservices_picture.go marshalTypedRPCRequest for
// Layer-2 methods that expect serialized JSON strings.
func marshalTypedJSON(v any) (string, error) {
	raw, err := json.Marshal(v)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}
