package vprocore

import (
	"reflect"
	"sync"
)

type contextStateSlot struct {
	once sync.Once
	val  any
}

// ContextState retrieves or initializes a typed, Layer-2-owned state container attached
// to s without embedding domain-specific ledger fields in Layer-1 ContextService.
// initFn executes outside s.extMu via sync.Once so it may safely register OnContextSwitch
// or RegisterSelectedListScopeGuard callbacks without re-entrant lock contention.
func ContextState[T any](s *ContextService, initFn func() *T) *T {
	if s == nil {
		return initFn()
	}
	key := reflect.TypeFor[*T]()
	s.extMu.Lock()
	if s.extensions == nil {
		s.extensions = make(map[reflect.Type]any)
	}
	raw, ok := s.extensions[key]
	if !ok {
		raw = &contextStateSlot{}
		s.extensions[key] = raw
	}
	slot := raw.(*contextStateSlot)
	s.extMu.Unlock()

	slot.once.Do(func() {
		slot.val = initFn()
	})
	return slot.val.(*T)
}

// OnContextSwitch registers an invalidation callback invoked whenever s switches active contexts
// or replaces its VLists.db standards catalogue.
func OnContextSwitch(s *ContextService, fn func()) {
	if s == nil || fn == nil {
		return
	}
	s.extMu.Lock()
	defer s.extMu.Unlock()
	s.switchHooks = append(s.switchHooks, fn)
}

func (s *ContextService) notifyContextSwitchHooks() {
	if s == nil {
		return
	}
	s.extMu.Lock()
	hooks := append([]func(){}, s.switchHooks...)
	s.extMu.Unlock()
	for _, fn := range hooks {
		fn()
	}
}

// RegisterSelectedListScopeGuard registers the Layer-2 report scope guard invoked by RequireSelectedListReportScope.
func RegisterSelectedListScopeGuard(s *ContextService, guard func(contextID string) error) {
	if s == nil || guard == nil {
		return
	}
	s.extMu.Lock()
	defer s.extMu.Unlock()
	s.selectedListScopeGuard = guard
}

// RequireSelectedListReportScope delegates to any registered Layer-2 report scope guard.
func (s *ContextService) RequireSelectedListReportScope(contextID string) error {
	return RequireSelectedListReportScope(s, contextID)
}

// RequireSelectedListReportScope delegates to any registered Layer-2 report scope guard.
func RequireSelectedListReportScope(s *ContextService, contextID string) error {
	if s == nil {
		return nil
	}
	s.extMu.Lock()
	guard := s.selectedListScopeGuard
	s.extMu.Unlock()
	if guard == nil {
		return nil
	}
	return guard(contextID)
}
