package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

const (
	activityQueueFileName = "activity_queue.json"
	maxQueuedEvents       = 500
	telemetryHTTPTimeout  = 5 * time.Second

	EventKindMachineEnrollment = "machine_enrollment"
	EventKindAppDownload       = "app_download"
	EventKindDatasetDownload   = "dataset_download"
	EventKindDatasetUpload     = "dataset_upload"
)

var eventKindPattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$`)

// PGActivitySink writes a single activity event to PostgreSQL becmaster.download_log (or test double).
type PGActivitySink func(ctx context.Context, evt ActivityEvent) error

// ActivityEvent represents one enrollment, download, or dataset upload telemetry record.
type ActivityEvent struct {
	EventID          string `json:"eventId"`
	EventKind        string `json:"eventKind"`
	OccurredAt       string `json:"occurredAt"`
	MachineID        string `json:"machineId"`
	AppVersion       string `json:"appVersion"`
	OS               string `json:"os"`
	Arch             string `json:"arch"`
	Actor            string `json:"actor"`
	RoleTier         string `json:"roleTier"`
	IdentityProvider string `json:"identityProvider"`
	DatasetName      string `json:"datasetName,omitempty"`
	PlotCount        int    `json:"plotCount"`
}

// ActivityRecordResult summarizes the immediate non-blocking outcome of recording an activity event.
type ActivityRecordResult struct {
	EventID      string `json:"eventId"`
	EventKind    string `json:"eventKind"`
	Queued       bool   `json:"queued"`
	PendingCount int    `json:"pendingCount"`
	RecordedAt   string `json:"recordedAt"`
	Deduplicated bool   `json:"deduplicated,omitempty"`
}

type activityQueueStore struct {
	Version             int             `json:"version"`
	LastEnrolledVersion string          `json:"lastEnrolledVersion,omitempty"`
	LastEnrolledAt      string          `json:"lastEnrolledAt,omitempty"`
	Events              []ActivityEvent `json:"events"`
}

func (m *Manager) activityQueuePath() (string, error) {
	dir, err := resolveConfigDir(m.configDir)
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, activityQueueFileName), nil
}

func (m *Manager) loadActivityQueueLocked() (activityQueueStore, error) {
	path, err := m.activityQueuePath()
	if err != nil {
		return activityQueueStore{}, err
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return activityQueueStore{Version: 1, Events: []ActivityEvent{}}, nil
		}
		return activityQueueStore{}, err
	}
	var store activityQueueStore
	if err := json.Unmarshal(raw, &store); err != nil {
		return activityQueueStore{Version: 1, Events: []ActivityEvent{}}, nil
	}
	if store.Version == 0 {
		store.Version = 1
	}
	if store.Events == nil {
		store.Events = []ActivityEvent{}
	}
	return store, nil
}

func (m *Manager) saveActivityQueueLocked(store activityQueueStore) error {
	path, err := m.activityQueuePath()
	if err != nil {
		return err
	}
	if store.Version == 0 {
		store.Version = 1
	}
	if len(store.Events) > maxQueuedEvents {
		store.Events = store.Events[len(store.Events)-maxQueuedEvents:]
	}
	data, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return writeFileAtomic0600(path, data)
}

// PendingActivityCount returns the number of locally queued telemetry events awaiting delivery.
func (m *Manager) PendingActivityCount() int {
	if m == nil {
		return 0
	}
	m.telemetryMu.Lock()
	defer m.telemetryMu.Unlock()
	store, err := m.loadActivityQueueLocked()
	if err != nil {
		return 0
	}
	return len(store.Events)
}

// EnsureMachineEnrollment records a one-time machine enrollment / app version event
// whenever the current appVersion has not yet been recorded on this machine.
func (m *Manager) EnsureMachineEnrollment(ctx context.Context, appVersion string) (ActivityRecordResult, error) {
	if m == nil {
		return ActivityRecordResult{}, errors.New("auth manager is unavailable")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return ActivityRecordResult{}, err
	}
	ver := strings.TrimSpace(appVersion)
	if ver == "" {
		ver = m.appVersion
	}
	if ver == "" {
		ver = "2.0.0-dev"
	}

	m.telemetryMu.Lock()
	store, err := m.loadActivityQueueLocked()
	if err != nil {
		m.telemetryMu.Unlock()
		return ActivityRecordResult{}, err
	}
	if store.LastEnrolledVersion == ver {
		res := ActivityRecordResult{
			EventKind:    EventKindMachineEnrollment,
			Queued:       false,
			PendingCount: len(store.Events),
			RecordedAt:   store.LastEnrolledAt,
			Deduplicated: true,
		}
		m.telemetryMu.Unlock()
		return res, nil
	}
	evt := m.buildActivityEvent(EventKindMachineEnrollment, ver, 0)
	evt.AppVersion = ver
	store.LastEnrolledVersion = ver
	store.LastEnrolledAt = evt.OccurredAt
	store.Events = append(store.Events, evt)
	if err := m.saveActivityQueueLocked(store); err != nil {
		m.telemetryMu.Unlock()
		return ActivityRecordResult{}, err
	}
	pending := len(store.Events)
	m.telemetryMu.Unlock()

	m.triggerAsyncFlush()
	return ActivityRecordResult{
		EventID:      evt.EventID,
		EventKind:    evt.EventKind,
		Queued:       true,
		PendingCount: pending,
		RecordedAt:   evt.OccurredAt,
	}, nil
}

// RecordActivity enqueues an activity event locally (offline-safe) and triggers a non-blocking flush.
func (m *Manager) RecordActivity(ctx context.Context, eventKind, datasetName string, plotCount int) (ActivityRecordResult, error) {
	if m == nil {
		return ActivityRecordResult{}, errors.New("auth manager is unavailable")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return ActivityRecordResult{}, err
	}
	kind := strings.ToLower(strings.TrimSpace(eventKind))
	if !eventKindPattern.MatchString(kind) {
		return ActivityRecordResult{}, errors.New("invalid activity event kind")
	}
	if plotCount < 0 {
		return ActivityRecordResult{}, errors.New("plot count must be zero or positive")
	}
	cleanDataset := strings.TrimSpace(datasetName)
	if len(cleanDataset) > 256 {
		cleanDataset = cleanDataset[:256]
	}

	evt := m.buildActivityEvent(kind, cleanDataset, plotCount)

	m.telemetryMu.Lock()
	store, err := m.loadActivityQueueLocked()
	if err != nil {
		m.telemetryMu.Unlock()
		return ActivityRecordResult{}, err
	}
	store.Events = append(store.Events, evt)
	if err := m.saveActivityQueueLocked(store); err != nil {
		m.telemetryMu.Unlock()
		return ActivityRecordResult{}, err
	}
	pending := len(store.Events)
	m.telemetryMu.Unlock()

	m.triggerAsyncFlush()
	return ActivityRecordResult{
		EventID:      evt.EventID,
		EventKind:    evt.EventKind,
		Queued:       true,
		PendingCount: pending,
		RecordedAt:   evt.OccurredAt,
	}, nil
}

func (m *Manager) buildActivityEvent(eventKind, datasetName string, plotCount int) ActivityEvent {
	summary := m.CachedSessionSummary()
	actor := summary.UserID
	if actor == "" {
		actor = "anonymous"
	}
	roleTier := summary.Role
	if roleTier == "" {
		roleTier = "anonymous"
	}
	ver := m.appVersion
	if ver == "" {
		ver = "2.0.0-dev"
	}
	return ActivityEvent{
		EventID:          uuid.NewString(),
		EventKind:        eventKind,
		OccurredAt:       m.now().Format(time.RFC3339),
		MachineID:        summary.MachineID,
		AppVersion:       ver,
		OS:               runtime.GOOS,
		Arch:             runtime.GOARCH,
		Actor:            actor,
		RoleTier:         roleTier,
		IdentityProvider: summary.IdentityProvider,
		DatasetName:      datasetName,
		PlotCount:        plotCount,
	}
}

func (m *Manager) triggerAsyncFlush() {
	if !m.hasTelemetrySinkConfigured() {
		return
	}
	go func() {
		flushCtx, cancel := context.WithTimeout(context.Background(), telemetryHTTPTimeout)
		defer cancel()
		_, _ = m.FlushTelemetry(flushCtx)
	}()
}

func (m *Manager) hasTelemetrySinkConfigured() bool {
	if m == nil {
		return false
	}
	if m.pgSink != nil {
		return true
	}
	if m.env("VPRO_TELEMETRY_URL") != "" {
		return true
	}
	if m.resolveTelemetryPGDSN() != "" {
		return true
	}
	return false
}

// FlushTelemetry attempts to deliver all queued events to the configured HTTP endpoint
// or PostgreSQL becmaster.download_log. Undelivered events stay safely queued on disk.
func (m *Manager) FlushTelemetry(ctx context.Context) (int, error) {
	if m == nil {
		return 0, errors.New("auth manager is unavailable")
	}
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return 0, err
	}

	m.flushMu.Lock()
	defer m.flushMu.Unlock()

	m.telemetryMu.Lock()
	store, err := m.loadActivityQueueLocked()
	if err != nil {
		m.telemetryMu.Unlock()
		return 0, err
	}
	if len(store.Events) == 0 {
		m.telemetryMu.Unlock()
		return 0, nil
	}
	batch := append([]ActivityEvent(nil), store.Events...)
	m.telemetryMu.Unlock()

	deliveredIDs := make(map[string]bool, len(batch))
	var deliveryErr error

	telemetryURL := m.env("VPRO_TELEMETRY_URL")
	if telemetryURL != "" {
		if err := m.postActivityBatchHTTP(ctx, telemetryURL, batch); err != nil {
			deliveryErr = err
		} else {
			for _, evt := range batch {
				deliveredIDs[evt.EventID] = true
			}
		}
	}

	if len(deliveredIDs) < len(batch) {
		remaining := make([]ActivityEvent, 0, len(batch)-len(deliveredIDs))
		for _, evt := range batch {
			if !deliveredIDs[evt.EventID] {
				remaining = append(remaining, evt)
			}
		}
		pgDelivered, pgErr := m.deliverToPostgresDownloadLog(ctx, remaining)
		for _, id := range pgDelivered {
			deliveredIDs[id] = true
		}
		if pgErr != nil && deliveryErr == nil {
			deliveryErr = pgErr
		}
	}

	if len(deliveredIDs) == 0 {
		return 0, deliveryErr
	}

	m.telemetryMu.Lock()
	latest, loadErr := m.loadActivityQueueLocked()
	if loadErr != nil {
		m.telemetryMu.Unlock()
		return len(deliveredIDs), loadErr
	}
	kept := make([]ActivityEvent, 0, len(latest.Events))
	for _, evt := range latest.Events {
		if !deliveredIDs[evt.EventID] {
			kept = append(kept, evt)
		}
	}
	latest.Events = kept
	saveErr := m.saveActivityQueueLocked(latest)
	m.telemetryMu.Unlock()
	if saveErr != nil {
		return len(deliveredIDs), saveErr
	}
	return len(deliveredIDs), deliveryErr
}

func (m *Manager) postActivityBatchHTTP(ctx context.Context, endpoint string, events []ActivityEvent) error {
	if err := requireHTTPSOrLoopback(endpoint); err != nil {
		return err
	}
	payload, err := json.Marshal(map[string]any{"events": events})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	token := m.env("VPRO_TELEMETRY_TOKEN")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := m.httpClient.Do(req)
	if err != nil {
		return wrapRedactedAuthError("post activity telemetry", err, token)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("activity telemetry endpoint returned HTTP %d", resp.StatusCode)
	}
	return nil
}

func (m *Manager) resolveTelemetryPGDSN() string {
	if dsn := m.env("VPRO_TELEMETRY_PG_URL"); dsn != "" {
		return dsn
	}
	if dsn := m.env("VPRO_PG_URL"); dsn != "" {
		return dsn
	}
	return ""
}

func (m *Manager) deliverToPostgresDownloadLog(ctx context.Context, events []ActivityEvent) ([]string, error) {
	if len(events) == 0 {
		return nil, nil
	}
	if m.pgSink != nil {
		var delivered []string
		for _, evt := range events {
			if err := m.pgSink(ctx, evt); err != nil {
				return delivered, wrapRedactedAuthError("write activity event to download_log", err)
			}
			delivered = append(delivered, evt.EventID)
		}
		return delivered, nil
	}

	dsn := m.resolveTelemetryPGDSN()
	if dsn == "" {
		return nil, nil
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		return nil, wrapRedactedAuthError("parse telemetry PostgreSQL config", err, dsn)
	}
	if err := requirePGTLSForRemoteHost(cfg); err != nil {
		return nil, err
	}
	conn, err := pgx.ConnectConfig(ctx, cfg)
	if err != nil {
		return nil, wrapRedactedAuthError("connect telemetry PostgreSQL", err, dsn, cfg.Password)
	}
	defer conn.Close(ctx)

	var delivered []string
	for _, evt := range events {
		filterJSON, mErr := json.Marshal(map[string]any{
			"event_id":          evt.EventID,
			"event_kind":        evt.EventKind,
			"occurred_at":       evt.OccurredAt,
			"machine_id":        evt.MachineID,
			"app_version":       evt.AppVersion,
			"os":                evt.OS,
			"arch":              evt.Arch,
			"identity_provider": evt.IdentityProvider,
			"dataset_name":      evt.DatasetName,
		})
		if mErr != nil {
			return delivered, mErr
		}
		_, execErr := conn.Exec(ctx,
			`INSERT INTO becmaster.download_log (actor, role_tier, filter_json, format, plot_count) VALUES ($1, $2, $3::jsonb, $4, $5)`,
			evt.Actor, evt.RoleTier, string(filterJSON), "activity:"+evt.EventKind, evt.PlotCount,
		)
		if execErr != nil {
			return delivered, wrapRedactedAuthError("insert becmaster.download_log activity", execErr, dsn, cfg.Password)
		}
		delivered = append(delivered, evt.EventID)
	}
	return delivered, nil
}

func requirePGTLSForRemoteHost(cfg *pgx.ConnConfig) error {
	if cfg == nil {
		return nil
	}
	if !isLoopbackHost(cfg.Host) && !strings.HasPrefix(cfg.Host, "/") && cfg.TLSConfig == nil {
		return errors.New("TLS is required for remote PostgreSQL telemetry hosts")
	}
	for _, fb := range cfg.Fallbacks {
		if fb != nil && !isLoopbackHost(fb.Host) && !strings.HasPrefix(fb.Host, "/") && fb.TLSConfig == nil {
			return errors.New("TLS is required for remote PostgreSQL telemetry hosts")
		}
	}
	return nil
}
