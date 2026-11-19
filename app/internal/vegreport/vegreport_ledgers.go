package vegreport

import (
	"errors"
	"sync"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type vegetationProjectScopeLedger struct {
	Mu      sync.Mutex
	Entries map[string]vprocore.VegetationProjectScopeEntry
}

func (ledger *vegetationProjectScopeLedger) Read(contextID string) vprocore.VegetationProjectScopeEntry {
	ledger.Mu.Lock()
	defer ledger.Mu.Unlock()
	return vprocore.CloneProjectScopeEntry(ledger.Entries[contextID])
}

type selectedUnitSelectionLedger struct {
	Mu      sync.Mutex
	Entries map[string]vprocore.SelectedUnitSelectionEntry
}

func (ledger *selectedUnitSelectionLedger) Read(contextID string) vprocore.SelectedUnitSelectionEntry {
	ledger.Mu.Lock()
	defer ledger.Mu.Unlock()
	entry := ledger.Entries[contextID]
	entry.Fields = append([]string{}, entry.Fields...)
	entry.Build = vprocore.CloneSelectedUnitBuild(entry.Build)
	return entry
}

type vegReportContextState struct {
	projectScopes          vegetationProjectScopeLedger
	selectedUnitSelections selectedUnitSelectionLedger
}

func vegReportState(s *vprocore.ContextService) *vegReportContextState {
	return vprocore.ContextState(s, func() *vegReportContextState {
		st := &vegReportContextState{}
		if s != nil {
			vprocore.OnContextSwitch(s, func() {
				st.selectedUnitSelections.Mu.Lock()
				st.selectedUnitSelections.Entries = nil
				st.selectedUnitSelections.Mu.Unlock()
				st.projectScopes.Mu.Lock()
				st.projectScopes.Entries = nil
				st.projectScopes.Mu.Unlock()
			})
			vprocore.RegisterSelectedListScopeGuard(s, func(contextID string) error {
				st.projectScopes.Mu.Lock()
				kind := st.projectScopes.Entries[contextID].SourceKind
				st.projectScopes.Mu.Unlock()
				if kind != "" && kind != vprocore.VegetationSelectedListScope {
					return errors.New("Long Vegetation has an explicit project report scope; this selected-list consumer is unavailable")
				}
				return nil
			})
		}
		return st
	})
}

func projectReportScopes(s *vprocore.ContextService) *vegetationProjectScopeLedger {
	return &vegReportState(s).projectScopes
}

func selectedUnitSelections(s *vprocore.ContextService) *selectedUnitSelectionLedger {
	return &vegReportState(s).selectedUnitSelections
}
