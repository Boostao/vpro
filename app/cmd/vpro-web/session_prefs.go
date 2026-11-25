package main

import (
	"container/list"
	"strings"
	"sync"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
)

const (
	defaultMaxSessions    = 256
	defaultSessionIdleTTL = 30 * time.Minute
	maxSessionIDLength    = 128
)

// WebSession holds per-browser-session ephemeral state: strictly in-memory
// DesktopConfig preferences, the session's current SelectionKey, plot-label PDF
// session binding, and a per-session ContextService carrier for Long Vegetation
// project-scope / selected-unit-selection ledgers.
type WebSession struct {
	ID         string
	Prefs      *vprocore.DesktopConfig
	lastAccess time.Time

	mu                 sync.Mutex
	selection          vprocore.SelectionKey
	hasSelection       bool
	plotLabelSessionID string

	scopeMu      sync.Mutex
	scopeCarrier *vprocore.ContextService
}

func (s *WebSession) Selection() (vprocore.SelectionKey, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.selection, s.hasSelection
}

func (s *WebSession) SetSelection(sel vprocore.SelectionKey) {
	s.mu.Lock()
	s.selection = sel
	s.hasSelection = true
	s.mu.Unlock()
}

func (s *WebSession) PlotLabelSessionID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.plotLabelSessionID
}

func (s *WebSession) SetPlotLabelSessionID(id string) {
	s.mu.Lock()
	s.plotLabelSessionID = id
	s.mu.Unlock()
}

// WithScopeCarrier executes fn with a per-session *vprocore.ContextService whose
// Projects/Plots are bound to lease.Context for the duration of this call,
// preserving session-scoped Long Vegetation ledgers across pooled leases without
// leaving dangling pointers after Release().
func (s *WebSession) WithScopeCarrier(lease *vprocore.ReadOnlyLease, fn func(*vprocore.ContextService) error) error {
	s.scopeMu.Lock()
	defer s.scopeMu.Unlock()
	if s.scopeCarrier == nil {
		s.scopeCarrier = &vprocore.ContextService{}
	}
	s.scopeCarrier.Projects = lease.Context.Projects
	s.scopeCarrier.Plots = lease.Context.Plots
	defer func() {
		s.scopeCarrier.Projects = nil
		s.scopeCarrier.Plots = nil
	}()
	return fn(s.scopeCarrier)
}

// SessionPrefsStore is a bounded LRU + idle-TTL store of ephemeral WebSessions
// keyed by the X-VPro-Session request header.
type SessionPrefsStore struct {
	maxSessions int
	idleTTL     time.Duration
	baseConfig  *vprocore.DesktopConfig

	mu      sync.Mutex
	lru     *list.List
	entries map[string]*list.Element
}

func NewSessionPrefsStore(maxSessions int, idleTTL time.Duration) (*SessionPrefsStore, error) {
	if maxSessions <= 0 {
		maxSessions = defaultMaxSessions
	}
	if idleTTL <= 0 {
		idleTTL = defaultSessionIdleTTL
	}
	baseCfg, err := vprocore.NewInMemoryDesktopConfig(nil)
	if err != nil {
		return nil, err
	}
	return &SessionPrefsStore{
		maxSessions: maxSessions,
		idleTTL:     idleTTL,
		baseConfig:  baseCfg,
		lru:         list.New(),
		entries:     make(map[string]*list.Element),
	}, nil
}

func normalizeSessionID(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	if len(trimmed) > maxSessionIDLength {
		trimmed = trimmed[:maxSessionIDLength]
	}
	for i := 0; i < len(trimmed); i++ {
		c := trimmed[i]
		if c < 0x21 || c > 0x7e {
			return ""
		}
	}
	return trimmed
}

// GetOrCreate returns the WebSession for rawSessionID (or an ephemeral unstored
// session if rawSessionID is empty/invalid), cloning from baseConfig on creation.
func (s *SessionPrefsStore) GetOrCreate(rawSessionID string) (*WebSession, error) {
	id := normalizeSessionID(rawSessionID)
	if id == "" {
		prefs, err := s.baseConfig.CloneInMemory()
		if err != nil {
			return nil, err
		}
		return &WebSession{
			ID:         "anonymous",
			Prefs:      prefs,
			lastAccess: time.Now(),
		}, nil
	}

	now := time.Now()
	s.mu.Lock()
	s.evictExpiredLocked(now)
	if elem, ok := s.entries[id]; ok {
		sess := elem.Value.(*WebSession)
		sess.lastAccess = now
		s.lru.MoveToFront(elem)
		s.mu.Unlock()
		return sess, nil
	}
	s.mu.Unlock()

	prefs, err := s.baseConfig.CloneInMemory()
	if err != nil {
		return nil, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if elem, ok := s.entries[id]; ok {
		sess := elem.Value.(*WebSession)
		sess.lastAccess = time.Now()
		s.lru.MoveToFront(elem)
		return sess, nil
	}
	sess := &WebSession{
		ID:         id,
		Prefs:      prefs,
		lastAccess: time.Now(),
	}
	elem := s.lru.PushFront(sess)
	s.entries[id] = elem
	for s.lru.Len() > s.maxSessions {
		oldest := s.lru.Back()
		if oldest == nil {
			break
		}
		s.lru.Remove(oldest)
		evicted := oldest.Value.(*WebSession)
		delete(s.entries, evicted.ID)
	}
	return sess, nil
}

func (s *SessionPrefsStore) evictExpiredLocked(now time.Time) {
	for elem := s.lru.Back(); elem != nil; {
		prev := elem.Prev()
		sess := elem.Value.(*WebSession)
		if now.Sub(sess.lastAccess) > s.idleTTL {
			s.lru.Remove(elem)
			delete(s.entries, sess.ID)
		} else {
			// LRU is ordered newest -> oldest, so we can stop once fresh.
			break
		}
		elem = prev
	}
}

func (s *SessionPrefsStore) Count() int {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.evictExpiredLocked(time.Now())
	return len(s.entries)
}
