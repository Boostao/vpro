package vprocore

import (
	"container/list"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/references"
	"github.com/boostao/vpro/app/internal/sqlutil"
)

const (
	DefaultReadOnlySlotsPerKey = 6
	DefaultReadOnlyMaxPools    = 16

	webContextIDPrefix   = "vproweb1:"
	maxWebContextIDBytes = 2048
)

var (
	// ErrPoolClosed is returned when Acquire or Reload is called on a closed ReadOnlyContextPool.
	ErrPoolClosed = errors.New("read-only context pool is closed")
	// ErrStaleWebContext is returned when a decoded web context ID belongs to a superseded catalog generation.
	ErrStaleWebContext = errors.New("web context generation is stale; reload snapshot selection")
	// ErrUnknownDataset is returned when a selection references a dataset ID not present in the active catalog.
	ErrUnknownDataset = errors.New("snapshot dataset not found")
)

// SnapshotDataset describes one immutable VP08 project database published in a SnapshotCatalog.
type SnapshotDataset struct {
	ID               string            `json:"id"`
	Label            string            `json:"label"`
	Project          string            `json:"project"`
	ProjectPath      string            `json:"projectPath"`
	SUPaths          map[string]string `json:"suPaths,omitempty"`
	HierarchyPaths   map[string]string `json:"hierarchyPaths,omitempty"`
	DefaultSU        string            `json:"defaultSu,omitempty"`
	DefaultHierarchy string            `json:"defaultHierarchy,omitempty"`
	PlotCount        int               `json:"plotCount,omitempty"`
	SUs              []SUInfo          `json:"sus,omitempty"`
	Hierarchies      []HierarchyInfo   `json:"hierarchies,omitempty"`
}

// SnapshotCatalog describes an atomic read-only snapshot generation served by ReadOnlyContextPool.
type SnapshotCatalog struct {
	Generation   string            `json:"generation"`
	SnapshotID   string            `json:"snapshotId,omitempty"`
	PublishedAt  string            `json:"publishedAt,omitempty"`
	Redacted     bool              `json:"redacted"`
	RootDir      string            `json:"rootDir,omitempty"`
	SupportPaths map[string]string `json:"supportPaths"`
	Datasets     []SnapshotDataset `json:"datasets"`
	Immutable    bool              `json:"immutable"`
}

// SelectionKey uniquely identifies a pooled read-only view (dataset + active SU + active Hierarchy).
type SelectionKey struct {
	DatasetID string `json:"datasetId"`
	SU        string `json:"su"`
	Hierarchy string `json:"hierarchy"`
}

func normalizeSelectionKey(k SelectionKey) SelectionKey {
	k.DatasetID = strings.TrimSpace(k.DatasetID)
	k.SU = strings.TrimSpace(k.SU)
	if k.SU == "" {
		k.SU = "None"
	}
	k.Hierarchy = strings.TrimSpace(k.Hierarchy)
	if k.Hierarchy == "" {
		k.Hierarchy = "None"
	}
	return k
}

type webContextTokenPayload struct {
	G string `json:"g"`
	D string `json:"d"`
	S string `json:"s"`
	H string `json:"h"`
}

// EncodeWebContextID encodes a stateless, URL/JSON-safe web context identity token
// binding a catalog generation and (datasetID, su, hierarchy) selection.
func EncodeWebContextID(generation, datasetID, su, hierarchy string) string {
	su = strings.TrimSpace(su)
	if su == "" {
		su = "None"
	}
	hierarchy = strings.TrimSpace(hierarchy)
	if hierarchy == "" {
		hierarchy = "None"
	}
	raw, err := json.Marshal(webContextTokenPayload{
		G: strings.TrimSpace(generation),
		D: strings.TrimSpace(datasetID),
		S: su,
		H: hierarchy,
	})
	if err != nil {
		return ""
	}
	return webContextIDPrefix + base64.RawURLEncoding.EncodeToString(raw)
}

// DecodeWebContextID decodes and validates a stateless web context identity token produced by EncodeWebContextID.
func DecodeWebContextID(id string) (generation, datasetID, su, hierarchy string, err error) {
	if len(id) == 0 || len(id) > maxWebContextIDBytes || !strings.HasPrefix(id, webContextIDPrefix) {
		return "", "", "", "", errors.New("invalid web context identity token")
	}
	encoded := id[len(webContextIDPrefix):]
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		return "", "", "", "", fmt.Errorf("decode web context identity token: %w", err)
	}
	var payload webContextTokenPayload
	if err := sqlutil.DecodeStrictJSON(raw, &payload); err != nil {
		return "", "", "", "", fmt.Errorf("parse web context identity payload: %w", err)
	}
	for _, field := range []string{payload.G, payload.D, payload.S, payload.H} {
		if !utf8.ValidString(field) || strings.ContainsRune(field, 0) {
			return "", "", "", "", errors.New("web context identity contains invalid text")
		}
	}
	if strings.TrimSpace(payload.G) == "" || strings.TrimSpace(payload.D) == "" {
		return "", "", "", "", errors.New("web context identity requires non-empty generation and datasetId")
	}
	if payload.S == "" {
		payload.S = "None"
	}
	if payload.H == "" {
		payload.H = "None"
	}
	if payload.S != "None" && !ProjectNamePattern.MatchString(payload.S) {
		return "", "", "", "", fmt.Errorf("invalid SU name %q in web context identity", payload.S)
	}
	if payload.H != "None" && !ProjectNamePattern.MatchString(payload.H) {
		return "", "", "", "", fmt.Errorf("invalid hierarchy name %q in web context identity", payload.H)
	}
	return payload.G, payload.D, payload.S, payload.H, nil
}

// ReadOnlyPoolOptions configures bounded slot concurrency and LRU capacity for ReadOnlyContextPool.
type ReadOnlyPoolOptions struct {
	SlotsPerKey int
	MaxPools    int
	SiteCodes   *references.SiteCodeService
	ParentCodes *references.ParentCodeService
}

// ReadOnlyPoolStats summarizes active and draining pool utilization for diagnostics/health checks.
type ReadOnlyPoolStats struct {
	Generation     string `json:"generation"`
	ActivePools    int    `json:"activePools"`
	IdleSlots      int    `json:"idleSlots"`
	InFlightLeases int    `json:"inFlightLeases"`
	DrainingPools  int    `json:"drainingPools"`
	Closed         bool   `json:"closed"`
}

// ReadOnlyLease holds an exclusive borrowed read-only ContextService bound to a session's in-memory DesktopConfig.
// Callers must invoke Release() when finished; Release() is idempotent.
type ReadOnlyLease struct {
	Context    *ContextService
	ContextID  string
	Generation string
	Selection  SelectionKey
	Dataset    SnapshotDataset

	releaseFn func()
	once      sync.Once
}

// Release returns the borrowed SqliteContext slot to its pool (or closes it if the pool is draining/closed).
func (l *ReadOnlyLease) Release() {
	if l == nil {
		return
	}
	l.once.Do(func() {
		if l.releaseFn != nil {
			l.releaseFn()
		}
	})
}

type keySlotPool struct {
	key         SelectionKey
	generation  string
	rootDir     string
	dataset     SnapshotDataset
	desktopSel  DesktopSelection
	coreSupport map[string]string
	immutable   bool

	sem chan struct{}

	mu        sync.Mutex
	idle      []*SqliteContext
	inFlight  int
	waiters   int
	draining  bool
	drained   bool
	drainedCh chan struct{}
}

func newKeySlotPool(
	key SelectionKey,
	generation string,
	rootDir string,
	dataset SnapshotDataset,
	desktopSel DesktopSelection,
	coreSupport map[string]string,
	immutable bool,
	slotsPerKey int,
) *keySlotPool {
	return &keySlotPool{
		key:         key,
		generation:  generation,
		rootDir:     rootDir,
		dataset:     cloneSnapshotDataset(dataset),
		desktopSel:  desktopSel,
		coreSupport: cloneStringMap(coreSupport),
		immutable:   immutable,
		sem:         make(chan struct{}, slotsPerKey),
		drainedCh:   make(chan struct{}),
	}
}

func (kp *keySlotPool) reserveWaiter() {
	kp.mu.Lock()
	kp.inFlight++
	kp.waiters++
	kp.mu.Unlock()
}

func (kp *keySlotPool) popIdleAndCompleteWait() *SqliteContext {
	kp.mu.Lock()
	kp.waiters--
	var sc *SqliteContext
	if n := len(kp.idle); n > 0 {
		sc = kp.idle[n-1]
		kp.idle[n-1] = nil
		kp.idle = kp.idle[:n-1]
	}
	kp.mu.Unlock()
	return sc
}

func (kp *keySlotPool) cancelWaiter() {
	var toClose []*SqliteContext
	kp.mu.Lock()
	kp.waiters--
	kp.inFlight--
	if kp.draining {
		if kp.inFlight == 0 {
			toClose = append(toClose, kp.idle...)
			kp.idle = nil
			if !kp.drained {
				kp.drained = true
				close(kp.drainedCh)
			}
		} else if len(kp.idle) > kp.waiters {
			excess := len(kp.idle) - kp.waiters
			toClose = append(toClose, kp.idle[:excess]...)
			kp.idle = kp.idle[excess:]
		}
	}
	kp.mu.Unlock()
	for _, sc := range toClose {
		_ = sc.Close()
	}
}

func (kp *keySlotPool) releaseWithoutSlot() {
	var toClose []*SqliteContext
	kp.mu.Lock()
	kp.inFlight--
	if kp.draining && kp.inFlight == 0 {
		toClose = append(toClose, kp.idle...)
		kp.idle = nil
		if !kp.drained {
			kp.drained = true
			close(kp.drainedCh)
		}
	}
	kp.mu.Unlock()
	<-kp.sem
	for _, sc := range toClose {
		_ = sc.Close()
	}
}

func (kp *keySlotPool) releaseSlot(sc *SqliteContext) {
	var toClose []*SqliteContext
	kp.mu.Lock()
	kp.inFlight--
	if kp.draining {
		if kp.waiters > 0 {
			kp.idle = append(kp.idle, sc)
		} else {
			toClose = append(toClose, sc)
		}
		if kp.inFlight == 0 {
			toClose = append(toClose, kp.idle...)
			kp.idle = nil
			if !kp.drained {
				kp.drained = true
				close(kp.drainedCh)
			}
		}
	} else {
		kp.idle = append(kp.idle, sc)
	}
	kp.mu.Unlock()
	<-kp.sem
	for _, item := range toClose {
		_ = item.Close()
	}
}

// beginDrain marks kp as draining and returns any excess idle SqliteContexts to close outside locks,
// along with whether kp is already fully drained.
func (kp *keySlotPool) beginDrain() ([]*SqliteContext, bool) {
	var toClose []*SqliteContext
	kp.mu.Lock()
	kp.draining = true
	if kp.inFlight == 0 {
		toClose = append(toClose, kp.idle...)
		kp.idle = nil
		if !kp.drained {
			kp.drained = true
			close(kp.drainedCh)
		}
	} else if len(kp.idle) > kp.waiters {
		excess := len(kp.idle) - kp.waiters
		toClose = append(toClose, kp.idle[:excess]...)
		kp.idle = kp.idle[excess:]
	}
	done := kp.drained
	kp.mu.Unlock()
	return toClose, done
}

func (kp *keySlotPool) isDrained() bool {
	kp.mu.Lock()
	done := kp.drained
	kp.mu.Unlock()
	return done
}

func (kp *keySlotPool) counts() (idle, inFlight int) {
	kp.mu.Lock()
	idle = len(kp.idle)
	inFlight = kp.inFlight
	kp.mu.Unlock()
	return idle, inFlight
}

type catalogGeneration struct {
	catalog      SnapshotCatalog
	generation   string
	coreSupport  map[string]string
	datasetsByID map[string]SnapshotDataset
	lru          *list.List
	entries      map[SelectionKey]*list.Element
}

func buildCatalogGeneration(catalog SnapshotCatalog) (*catalogGeneration, error) {
	generation := strings.TrimSpace(catalog.Generation)
	if generation == "" {
		generation = strings.TrimSpace(catalog.SnapshotID)
	}
	if generation == "" {
		return nil, errors.New("snapshot catalog requires a non-empty generation or snapshotId")
	}
	if !utf8.ValidString(generation) || strings.ContainsRune(generation, 0) {
		return nil, errors.New("snapshot catalog generation contains invalid text")
	}
	if len(catalog.Datasets) == 0 {
		return nil, errors.New("snapshot catalog requires at least one dataset")
	}

	// Validate and canonicalize support database paths.
	coreSupport := make(map[string]string, len(DatabaseFamilySeeds))
	resolvedSupport := make(map[string]string, len(catalog.SupportPaths))
	allowedRoles := make(map[string]bool, len(DatabaseFamilySeeds)+1)
	for _, seed := range DatabaseFamilySeeds {
		allowedRoles[seed.Name] = true
	}
	allowedRoles["VPics"] = true

	for role, rawPath := range catalog.SupportPaths {
		if !allowedRoles[role] {
			return nil, fmt.Errorf("unknown support database role %q in snapshot catalog", role)
		}
		if role == "VPics" && strings.TrimSpace(rawPath) == "" {
			continue
		}
		resolved, err := ExistingDatabasePath(rawPath)
		if err != nil {
			return nil, fmt.Errorf("snapshot support %s: %w", role, err)
		}
		resolvedSupport[role] = resolved
	}
	for _, seed := range DatabaseFamilySeeds {
		path, ok := resolvedSupport[seed.Name]
		if !ok {
			return nil, fmt.Errorf("snapshot catalog missing required support role %s", seed.Name)
		}
		coreSupport[seed.Name] = path
	}

	datasetsByID := make(map[string]SnapshotDataset, len(catalog.Datasets))
	normalizedDatasets := make([]SnapshotDataset, 0, len(catalog.Datasets))
	for _, rawDS := range catalog.Datasets {
		ds := cloneSnapshotDataset(rawDS)
		ds.ID = strings.TrimSpace(ds.ID)
		ds.Project = strings.TrimSpace(ds.Project)
		if ds.ID == "" {
			return nil, errors.New("snapshot dataset requires a non-empty id")
		}
		if !utf8.ValidString(ds.ID) || strings.ContainsRune(ds.ID, 0) {
			return nil, fmt.Errorf("snapshot dataset id %q contains invalid text", ds.ID)
		}
		if _, dup := datasetsByID[ds.ID]; dup {
			return nil, fmt.Errorf("duplicate snapshot dataset id %q", ds.ID)
		}
		if !ProjectNamePattern.MatchString(ds.Project) {
			return nil, fmt.Errorf("snapshot dataset %q has invalid project name %q", ds.ID, ds.Project)
		}
		resolvedProject, err := ExistingDatabasePath(ds.ProjectPath)
		if err != nil {
			return nil, fmt.Errorf("snapshot dataset %q project path: %w", ds.ID, err)
		}
		ds.ProjectPath = resolvedProject
		if ds.Label == "" {
			ds.Label = ds.Project
		}
		if strings.TrimSpace(ds.DefaultSU) == "" {
			ds.DefaultSU = "None"
		}
		if strings.TrimSpace(ds.DefaultHierarchy) == "" {
			ds.DefaultHierarchy = "None"
		}
		for name, p := range ds.SUPaths {
			resolved, err := ExistingDatabasePath(p)
			if err != nil {
				return nil, fmt.Errorf("snapshot dataset %q SU %q path: %w", ds.ID, name, err)
			}
			ds.SUPaths[name] = resolved
		}
		for name, p := range ds.HierarchyPaths {
			resolved, err := ExistingDatabasePath(p)
			if err != nil {
				return nil, fmt.Errorf("snapshot dataset %q hierarchy %q path: %w", ds.ID, name, err)
			}
			ds.HierarchyPaths[name] = resolved
		}
		datasetsByID[ds.ID] = ds
		normalizedDatasets = append(normalizedDatasets, ds)
	}

	normalizedCatalog := SnapshotCatalog{
		Generation:   generation,
		SnapshotID:   catalog.SnapshotID,
		PublishedAt:  catalog.PublishedAt,
		Redacted:     catalog.Redacted,
		RootDir:      catalog.RootDir,
		SupportPaths: resolvedSupport,
		Datasets:     normalizedDatasets,
		Immutable:    catalog.Immutable,
	}
	if normalizedCatalog.SnapshotID == "" {
		normalizedCatalog.SnapshotID = generation
	}
	if normalizedCatalog.RootDir == "" && len(normalizedDatasets) > 0 {
		normalizedCatalog.RootDir = filepath.Dir(normalizedDatasets[0].ProjectPath)
	}

	return &catalogGeneration{
		catalog:      normalizedCatalog,
		generation:   generation,
		coreSupport:  coreSupport,
		datasetsByID: datasetsByID,
		lru:          list.New(),
		entries:      make(map[SelectionKey]*list.Element),
	}, nil
}

// ReadOnlyContextPool manages a bounded LRU of concurrent read-only SqliteContext slot pools
// keyed by SelectionKey{DatasetID, SU, Hierarchy}, supporting stateless web context tokens,
// per-session in-memory DesktopConfig isolation, and atomic zero-drop snapshot reloads.
type ReadOnlyContextPool struct {
	slotsPerKey int
	maxPools    int
	siteCodes   *references.SiteCodeService
	parentCodes *references.ParentCodeService

	mu       sync.Mutex
	active   *catalogGeneration
	draining []*keySlotPool
	closed   bool
}

// NewReadOnlyContextPool creates a concurrent read-only context pool backed by catalog.
func NewReadOnlyContextPool(catalog SnapshotCatalog, opts ...ReadOnlyPoolOptions) (*ReadOnlyContextPool, error) {
	gen, err := buildCatalogGeneration(catalog)
	if err != nil {
		return nil, err
	}
	var cfg ReadOnlyPoolOptions
	if len(opts) > 0 {
		cfg = opts[0]
	}
	slotsPerKey := cfg.SlotsPerKey
	if slotsPerKey <= 0 {
		slotsPerKey = DefaultReadOnlySlotsPerKey
	}
	maxPools := cfg.MaxPools
	if maxPools <= 0 {
		maxPools = DefaultReadOnlyMaxPools
	}
	return &ReadOnlyContextPool{
		slotsPerKey: slotsPerKey,
		maxPools:    maxPools,
		siteCodes:   cfg.SiteCodes,
		parentCodes: cfg.ParentCodes,
		active:      gen,
	}, nil
}

// Generation returns the active catalog generation identifier.
func (p *ReadOnlyContextPool) Generation() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.active == nil {
		return ""
	}
	return p.active.generation
}

// Catalog returns a defensive copy of the currently active SnapshotCatalog.
func (p *ReadOnlyContextPool) Catalog() SnapshotCatalog {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.active == nil {
		return SnapshotCatalog{}
	}
	return cloneSnapshotCatalog(p.active.catalog)
}

// Stats returns a point-in-time snapshot of pool capacity, active leases, and draining pools.
func (p *ReadOnlyContextPool) Stats() ReadOnlyPoolStats {
	p.mu.Lock()
	p.pruneDrainedLocked()
	stats := ReadOnlyPoolStats{
		Closed: p.closed,
	}
	var activePools []*keySlotPool
	if p.active != nil {
		stats.Generation = p.active.generation
		stats.ActivePools = len(p.active.entries)
		activePools = make([]*keySlotPool, 0, len(p.active.entries))
		for _, elem := range p.active.entries {
			activePools = append(activePools, elem.Value.(*keySlotPool))
		}
	}
	draining := append([]*keySlotPool(nil), p.draining...)
	p.mu.Unlock()

	for _, kp := range activePools {
		idle, inFlight := kp.counts()
		stats.IdleSlots += idle
		stats.InFlightLeases += inFlight
	}
	for _, kp := range draining {
		if !kp.isDrained() {
			stats.DrainingPools++
			idle, inFlight := kp.counts()
			stats.IdleSlots += idle
			stats.InFlightLeases += inFlight
		}
	}
	return stats
}

// Acquire borrows an independent read-only *ContextService slot for selection bound to sessionPrefs.
// Multiple concurrent Acquire calls for the same SelectionKey execute in parallel across up to SlotsPerKey
// independent SqliteContext instances without serializing on a shared desktop mutex.
// If sessionPrefs is nil, an isolated default in-memory DesktopConfig is allocated for the lease.
func (p *ReadOnlyContextPool) Acquire(ctx context.Context, selection SelectionKey, sessionPrefs *DesktopConfig) (*ReadOnlyLease, error) {
	return p.acquire(ctx, "", selection, sessionPrefs)
}

// AcquireByContextID decodes a stateless web context ID, verifies its generation matches the active
// catalog atomically (returning ErrStaleWebContext if superseded by Reload), and borrows a slot.
func (p *ReadOnlyContextPool) AcquireByContextID(ctx context.Context, contextID string, sessionPrefs *DesktopConfig) (*ReadOnlyLease, error) {
	gen, datasetID, su, hierarchy, err := DecodeWebContextID(contextID)
	if err != nil {
		return nil, err
	}
	return p.acquire(ctx, gen, SelectionKey{DatasetID: datasetID, SU: su, Hierarchy: hierarchy}, sessionPrefs)
}

func (p *ReadOnlyContextPool) acquire(ctx context.Context, expectedGeneration string, selection SelectionKey, sessionPrefs *DesktopConfig) (*ReadOnlyLease, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}

	prefs := sessionPrefs
	if prefs == nil {
		var err error
		prefs, err = NewInMemoryDesktopConfig(nil)
		if err != nil {
			return nil, fmt.Errorf("initialize ephemeral session preferences: %w", err)
		}
	} else if !prefs.IsMemoryOnly() {
		return nil, errors.New("read-only context pool requires an in-memory DesktopConfig")
	}

	key := normalizeSelectionKey(selection)
	if key.DatasetID == "" {
		return nil, fmt.Errorf("%w: empty datasetId", ErrUnknownDataset)
	}
	if key.SU != "None" && !ProjectNamePattern.MatchString(key.SU) {
		return nil, fmt.Errorf("invalid SU name %q", key.SU)
	}
	if key.Hierarchy != "None" && !ProjectNamePattern.MatchString(key.Hierarchy) {
		return nil, fmt.Errorf("invalid hierarchy name %q", key.Hierarchy)
	}

	var (
		kp          *keySlotPool
		evictedClose []*SqliteContext
	)

	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return nil, ErrPoolClosed
	}
	p.pruneDrainedLocked()
	gen := p.active
	if gen == nil {
		p.mu.Unlock()
		return nil, ErrPoolClosed
	}
	if expectedGeneration != "" && gen.generation != expectedGeneration {
		p.mu.Unlock()
		return nil, fmt.Errorf("%w: token generation %q != active %q", ErrStaleWebContext, expectedGeneration, gen.generation)
	}
	ds, ok := gen.datasetsByID[key.DatasetID]
	if !ok {
		p.mu.Unlock()
		return nil, fmt.Errorf("%w: %q", ErrUnknownDataset, key.DatasetID)
	}

	if elem, exists := gen.entries[key]; exists {
		gen.lru.MoveToFront(elem)
		kp = elem.Value.(*keySlotPool)
	} else {
		desktopSel := resolveDatasetDesktopSelection(ds, key)
		kp = newKeySlotPool(
			key,
			gen.generation,
			gen.catalog.RootDir,
			ds,
			desktopSel,
			gen.coreSupport,
			gen.catalog.Immutable,
			p.slotsPerKey,
		)
		elem := gen.lru.PushFront(kp)
		gen.entries[key] = elem

		if gen.lru.Len() > p.maxPools {
			oldest := gen.lru.Back()
			if oldest != nil {
				gen.lru.Remove(oldest)
				evicted := oldest.Value.(*keySlotPool)
				delete(gen.entries, evicted.key)
				var done bool
				evictedClose, done = evicted.beginDrain()
				if !done {
					p.draining = append(p.draining, evicted)
				}
			}
		}
	}
	kp.reserveWaiter()
	p.mu.Unlock()

	for _, sc := range evictedClose {
		_ = sc.Close()
	}

	// Wait for a slot permit on this SelectionKey without holding p.mu.
	select {
	case kp.sem <- struct{}{}:
	case <-ctx.Done():
		kp.cancelWaiter()
		return nil, ctx.Err()
	}

	if err := ctx.Err(); err != nil {
		<-kp.sem
		kp.cancelWaiter()
		return nil, err
	}

	sc := kp.popIdleAndCompleteWait()
	if sc == nil {
		var err error
		sc, err = NewReadOnlySQLiteContext(ctx, kp.desktopSel, kp.coreSupport, nil, kp.immutable)
		if err != nil {
			kp.releaseWithoutSlot()
			return nil, err
		}
	}

	contextID := EncodeWebContextID(kp.generation, kp.key.DatasetID, kp.key.SU, kp.key.Hierarchy)
	hierarchyFile := ""
	if kp.desktopSel.Hierarchy != "None" && kp.desktopSel.HierarchyPath != "" {
		hierarchyFile = filepath.Base(kp.desktopSel.HierarchyPath)
	}
	projects := &ProjectService{
		Root:            kp.rootDir,
		Config:          "",
		Active:          kp.desktopSel.Project,
		ActiveSU:        kp.desktopSel.SU,
		activeHierarchy: kp.desktopSel.Hierarchy,
		hierarchyFile:   hierarchyFile,
		Preferences:     prefs,
		Sqlite:          sc,
		SupportPaths:    cloneStringMap(kp.coreSupport),
		ContextID:       contextID,
	}
	plots := &PlotService{
		Projects:      projects,
		AuditStrength: 0,
		CurrentUser:   "WebReader",
		SiteCodes:     p.siteCodes,
		ParentCodes:   p.parentCodes,
	}
	ctxService, err := NewContextService(projects, plots)
	if err != nil {
		kp.releaseSlot(sc)
		return nil, err
	}

	return &ReadOnlyLease{
		Context:    ctxService,
		ContextID:  contextID,
		Generation: kp.generation,
		Selection:  kp.key,
		Dataset:    cloneSnapshotDataset(kp.dataset),
		releaseFn: func() {
			kp.releaseSlot(sc)
		},
	}, nil
}

// Reload atomically replaces the active SnapshotCatalog with newCatalog.
// All new Acquire calls immediately route to newCatalog while any in-flight leases on the
// previous generation finish cleanly without interruption; old SQLite handles close as soon
// as idle or released.
func (p *ReadOnlyContextPool) Reload(newCatalog SnapshotCatalog) error {
	nextGen, err := buildCatalogGeneration(newCatalog)
	if err != nil {
		return err
	}

	var toClose []*SqliteContext
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return ErrPoolClosed
	}
	oldGen := p.active
	p.active = nextGen
	if oldGen != nil {
		for _, elem := range oldGen.entries {
			kp := elem.Value.(*keySlotPool)
			idleToClose, done := kp.beginDrain()
			toClose = append(toClose, idleToClose...)
			if !done {
				p.draining = append(p.draining, kp)
			}
		}
	}
	p.pruneDrainedLocked()
	p.mu.Unlock()

	for _, sc := range toClose {
		_ = sc.Close()
	}
	return nil
}

// WaitDrained blocks until all previously evicted or reloaded slot pools have finished
// their in-flight reads and closed their SQLite handles, or until ctx is cancelled.
func (p *ReadOnlyContextPool) WaitDrained(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}
	for {
		p.mu.Lock()
		p.pruneDrainedLocked()
		if len(p.draining) == 0 {
			p.mu.Unlock()
			return nil
		}
		ch := p.draining[0].drainedCh
		p.mu.Unlock()

		select {
		case <-ch:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
}

// Close marks the pool closed, closes all idle SQLite handles immediately, and marks any
// active in-flight slots to close automatically on Release().
func (p *ReadOnlyContextPool) Close() error {
	var toClose []*SqliteContext
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return nil
	}
	p.closed = true
	oldGen := p.active
	p.active = nil
	if oldGen != nil {
		for _, elem := range oldGen.entries {
			kp := elem.Value.(*keySlotPool)
			idleToClose, done := kp.beginDrain()
			toClose = append(toClose, idleToClose...)
			if !done {
				p.draining = append(p.draining, kp)
			}
		}
	}
	p.pruneDrainedLocked()
	p.mu.Unlock()

	var closeErr error
	for _, sc := range toClose {
		closeErr = errors.Join(closeErr, sc.Close())
	}
	return closeErr
}

func (p *ReadOnlyContextPool) pruneDrainedLocked() {
	if len(p.draining) == 0 {
		return
	}
	kept := p.draining[:0]
	for _, kp := range p.draining {
		if !kp.isDrained() {
			kept = append(kept, kp)
		}
	}
	for i := len(kept); i < len(p.draining); i++ {
		p.draining[i] = nil
	}
	p.draining = kept
}

// DiscoverDatasetSelections discovers all compatible SUs and Hierarchies for datasetID in the active catalog
// strictly in read-only mode (honoring the catalog's Immutable flag).
func (p *ReadOnlyContextPool) DiscoverDatasetSelections(ctx context.Context, datasetID string) ([]SUInfo, []HierarchyInfo, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	p.mu.Lock()
	if p.closed || p.active == nil {
		p.mu.Unlock()
		return nil, nil, ErrPoolClosed
	}
	ds, ok := p.active.datasetsByID[strings.TrimSpace(datasetID)]
	immutable := p.active.catalog.Immutable
	p.mu.Unlock()
	if !ok {
		return nil, nil, fmt.Errorf("%w: %q", ErrUnknownDataset, datasetID)
	}
	return DiscoverDatasetSelectionsReadOnly(ctx, ds, immutable)
}

// DiscoverDatasetSUsReadOnly lists compatible *_SU tables in a dataset's project database
// and any configured external SUPaths strictly in read-only mode.
func DiscoverDatasetSUsReadOnly(ctx context.Context, dataset SnapshotDataset, immutable bool) ([]SUInfo, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	paths := collectUniqueDatasetPaths(dataset.ProjectPath, dataset.SUPaths)
	var out []SUInfo
	for _, path := range paths {
		found, err := DiscoverSUsReadOnly(ctx, path, immutable)
		if err != nil {
			return nil, err
		}
		for _, su := range found {
			if !su.Compatible {
				continue
			}
			if !slices.ContainsFunc(out, func(existing SUInfo) bool {
				return existing.Name == su.Name && SameDesktopPath(existing.Path, su.Path)
			}) {
				out = append(out, su)
			}
		}
	}
	slices.SortFunc(out, func(left, right SUInfo) int {
		if cmp := strings.Compare(left.Name, right.Name); cmp != 0 {
			return cmp
		}
		return strings.Compare(left.Path, right.Path)
	})
	return out, nil
}

// DiscoverDatasetHierarchiesReadOnly lists compatible *_Hierarchy tables in a dataset's project database
// and any configured external HierarchyPaths strictly in read-only mode.
func DiscoverDatasetHierarchiesReadOnly(ctx context.Context, dataset SnapshotDataset, immutable bool) ([]HierarchyInfo, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	paths := collectUniqueDatasetPaths(dataset.ProjectPath, dataset.HierarchyPaths)
	var out []HierarchyInfo
	for _, path := range paths {
		found, err := DiscoverHierarchiesReadOnly(ctx, path, immutable)
		if err != nil {
			return nil, err
		}
		for _, h := range found {
			if !h.Compatible {
				continue
			}
			if !slices.ContainsFunc(out, func(existing HierarchyInfo) bool {
				return existing.Name == h.Name && SameDesktopPath(existing.Path, h.Path)
			}) {
				out = append(out, h)
			}
		}
	}
	slices.SortFunc(out, func(left, right HierarchyInfo) int {
		if cmp := strings.Compare(left.Name, right.Name); cmp != 0 {
			return cmp
		}
		return strings.Compare(left.Path, right.Path)
	})
	return out, nil
}

// DiscoverDatasetSelectionsReadOnly discovers compatible SUs and Hierarchies for a dataset in read-only mode.
func DiscoverDatasetSelectionsReadOnly(ctx context.Context, dataset SnapshotDataset, immutable bool) ([]SUInfo, []HierarchyInfo, error) {
	sus, err := DiscoverDatasetSUsReadOnly(ctx, dataset, immutable)
	if err != nil {
		return nil, nil, err
	}
	hierarchies, err := DiscoverDatasetHierarchiesReadOnly(ctx, dataset, immutable)
	if err != nil {
		return nil, nil, err
	}
	return sus, hierarchies, nil
}

func collectUniqueDatasetPaths(primary string, extra map[string]string) []string {
	var paths []string
	add := func(p string) {
		p = strings.TrimSpace(p)
		if p == "" {
			return
		}
		if !slices.ContainsFunc(paths, func(existing string) bool { return SameDesktopPath(existing, p) }) {
			paths = append(paths, p)
		}
	}
	add(primary)
	keys := make([]string, 0, len(extra))
	for k := range extra {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	for _, k := range keys {
		add(extra[k])
	}
	return paths
}

func resolveDatasetDesktopSelection(ds SnapshotDataset, key SelectionKey) DesktopSelection {
	sel := DesktopSelection{
		Project:     ds.Project,
		ProjectPath: ds.ProjectPath,
		SU:          key.SU,
		Hierarchy:   key.Hierarchy,
	}
	if key.SU != "None" {
		if p := strings.TrimSpace(ds.SUPaths[key.SU]); p != "" {
			sel.SUPath = p
		} else {
			for _, su := range ds.SUs {
				if su.Name == key.SU && strings.TrimSpace(su.Path) != "" {
					sel.SUPath = su.Path
					break
				}
			}
			if sel.SUPath == "" {
				sel.SUPath = ds.ProjectPath
			}
		}
	}
	if key.Hierarchy != "None" {
		if p := strings.TrimSpace(ds.HierarchyPaths[key.Hierarchy]); p != "" {
			sel.HierarchyPath = p
		} else {
			for _, h := range ds.Hierarchies {
				if h.Name == key.Hierarchy && strings.TrimSpace(h.Path) != "" {
					sel.HierarchyPath = h.Path
					break
				}
			}
			if sel.HierarchyPath == "" {
				sel.HierarchyPath = ds.ProjectPath
			}
		}
	}
	return sel
}

func cloneStringMap(src map[string]string) map[string]string {
	if src == nil {
		return nil
	}
	dst := make(map[string]string, len(src))
	for k, v := range src {
		dst[k] = v
	}
	return dst
}

func cloneSnapshotDataset(src SnapshotDataset) SnapshotDataset {
	dst := src
	dst.SUPaths = cloneStringMap(src.SUPaths)
	dst.HierarchyPaths = cloneStringMap(src.HierarchyPaths)
	if src.SUs != nil {
		dst.SUs = append([]SUInfo(nil), src.SUs...)
	}
	if src.Hierarchies != nil {
		dst.Hierarchies = append([]HierarchyInfo(nil), src.Hierarchies...)
	}
	return dst
}

func cloneSnapshotCatalog(src SnapshotCatalog) SnapshotCatalog {
	dst := src
	dst.SupportPaths = cloneStringMap(src.SupportPaths)
	if src.Datasets != nil {
		dst.Datasets = make([]SnapshotDataset, len(src.Datasets))
		for i, ds := range src.Datasets {
			dst.Datasets[i] = cloneSnapshotDataset(ds)
		}
	}
	return dst
}
