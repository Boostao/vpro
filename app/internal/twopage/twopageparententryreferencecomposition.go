package twopage

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"reflect"
	"sync"

	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/vprocore"
)

const twoPageStaticRefCacheMaxEntries = 16

type twoPageStaticReaderPtrs struct {
	region     uintptr
	site       uintptr
	parent     uintptr
	geology    uintptr
	bec        uintptr
	ecosection uintptr
	quality    uintptr
	soil       uintptr
}

type twoPageStaticRefCacheKey struct {
	owner      *vprocore.SqliteContext
	contextID  string
	form       string
	listsAlias string
	readers    twoPageStaticReaderPtrs
}

type twoPageStaticVListsStamp struct {
	dataVersion int64
	modUnixNano int64
	size        int64
}

type twoPageStaticRefCacheEntry struct {
	stamp  twoPageStaticVListsStamp
	fields map[string]sourceform.SourceParentSharedReference
}

type twoPageStaticRefCacheStore struct {
	mu         sync.RWMutex
	entries    map[twoPageStaticRefCacheKey]*twoPageStaticRefCacheEntry
	registered map[*vprocore.SqliteContext]bool
}

var twoPageStaticRefCache = &twoPageStaticRefCacheStore{
	entries:    make(map[twoPageStaticRefCacheKey]*twoPageStaticRefCacheEntry),
	registered: make(map[*vprocore.SqliteContext]bool),
}

func (s *twoPageStaticRefCacheStore) get(key twoPageStaticRefCacheKey, stamp twoPageStaticVListsStamp) (map[string]sourceform.SourceParentSharedReference, bool) {
	s.mu.RLock()
	entry, ok := s.entries[key]
	if !ok || entry.stamp != stamp {
		s.mu.RUnlock()
		return nil, false
	}
	fields := entry.fields
	s.mu.RUnlock()
	return fields, true
}

func (s *twoPageStaticRefCacheStore) put(key twoPageStaticRefCacheKey, stamp twoPageStaticVListsStamp, fields map[string]sourceform.SourceParentSharedReference) {
	s.mu.Lock()
	if _, exists := s.entries[key]; !exists && len(s.entries) >= twoPageStaticRefCacheMaxEntries {
		clear(s.entries)
	}
	s.entries[key] = &twoPageStaticRefCacheEntry{stamp: stamp, fields: fields}
	needHook := !s.registered[key.owner]
	if needHook {
		s.registered[key.owner] = true
	}
	s.mu.Unlock()
	if needHook {
		owner := key.owner
		owner.OnClose(func() {
			s.evictOwner(owner)
		})
	}
}

func (s *twoPageStaticRefCacheStore) evictOwner(owner *vprocore.SqliteContext) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.registered, owner)
	for key := range s.entries {
		if key.owner == owner {
			delete(s.entries, key)
		}
	}
}

func (s *twoPageStaticRefCacheStore) hasOwnerForTest(owner *vprocore.SqliteContext) bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for key := range s.entries {
		if key.owner == owner {
			return true
		}
	}
	return false
}

func isTwoPageStaticReferenceField(field TwoPageEntryReferenceField) bool {
	if field.Column == "SubZone" || field.Column == "SiteSeries" {
		return false
	}
	switch field.Reader {
	case "project", "working-unit", "bec-series":
		return false
	default:
		return true
	}
}

func readerPointerIdentity(iface any) (uintptr, bool) {
	if iface == nil {
		return 0, false
	}
	v := reflect.ValueOf(iface)
	if v.Kind() != reflect.Pointer || v.IsNil() {
		return 0, false
	}
	return v.Pointer(), true
}

func twoPageStaticReadersKey(readers TwoPageEntryReferenceReaders) (twoPageStaticReaderPtrs, bool) {
	var ptrs twoPageStaticReaderPtrs
	var ok bool
	if ptrs.region, ok = readerPointerIdentity(readers.Shared.Region); !ok {
		return ptrs, false
	}
	if ptrs.site, ok = readerPointerIdentity(readers.Shared.Site); !ok {
		return ptrs, false
	}
	if ptrs.parent, ok = readerPointerIdentity(readers.Shared.Parent); !ok {
		return ptrs, false
	}
	if ptrs.geology, ok = readerPointerIdentity(readers.Shared.Geology); !ok {
		return ptrs, false
	}
	if ptrs.bec, ok = readerPointerIdentity(readers.Shared.Bec); !ok {
		return ptrs, false
	}
	if ptrs.ecosection, ok = readerPointerIdentity(readers.Ecosection); !ok {
		return ptrs, false
	}
	if ptrs.quality, ok = readerPointerIdentity(readers.Quality); !ok {
		return ptrs, false
	}
	if ptrs.soil, ok = readerPointerIdentity(readers.Soil); !ok {
		return ptrs, false
	}
	return ptrs, true
}

func readTwoPageVListsStamp(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext, listsAlias string) (twoPageStaticVListsStamp, bool) {
	path := owner.Attachments["VLists"]
	if path == "" || listsAlias == "" {
		return twoPageStaticVListsStamp{}, false
	}
	info, err := os.Stat(path)
	if err != nil {
		return twoPageStaticVListsStamp{}, false
	}
	var dataVersion int64
	if err := tx.QueryRowContext(ctx, `PRAGMA `+vprocore.QuoteHeaderIdentifier(listsAlias)+`.data_version`).Scan(&dataVersion); err != nil {
		return twoPageStaticVListsStamp{}, false
	}
	return twoPageStaticVListsStamp{
		dataVersion: dataVersion,
		modUnixNano: info.ModTime().UnixNano(),
		size:        info.Size(),
	}, true
}

func cloneStringPtr(value *string) *string {
	if value == nil {
		return nil
	}
	copied := *value
	return &copied
}

func cloneProjectMetadataTable(table vprocore.ProjectMetadataTable) vprocore.ProjectMetadataTable {
	var cols []vprocore.ProjectMetadataColumn
	if table.Columns != nil {
		cols = make([]vprocore.ProjectMetadataColumn, len(table.Columns))
		copy(cols, table.Columns)
	}
	var rows []vprocore.ProjectMetadataRow
	if table.Rows != nil {
		rows = make([]vprocore.ProjectMetadataRow, len(table.Rows))
		for i, row := range table.Rows {
			var cells []vprocore.ProjectMetadataCell
			if row.Cells != nil {
				cells = make([]vprocore.ProjectMetadataCell, len(row.Cells))
				for j, cell := range row.Cells {
					cells[j] = vprocore.CloneSiteUnitCell(cell)
				}
			}
			rows[i] = vprocore.ProjectMetadataRow{RowID: row.RowID, Cells: cells}
		}
	}
	return vprocore.ProjectMetadataTable{Columns: cols, Rows: rows}
}

func cloneSourceParentSharedReference(ref sourceform.SourceParentSharedReference) sourceform.SourceParentSharedReference {
	cloned := ref
	cloned.Definitions = cloneProjectMetadataTable(ref.Definitions)
	if ref.Choices != nil {
		cloned.Choices = make([]sourceform.SourceParentSharedReferenceChoice, len(ref.Choices))
		for i, choice := range ref.Choices {
			cloned.Choices[i] = sourceform.SourceParentSharedReferenceChoice{
				RowID:       choice.RowID,
				Code:        cloneStringPtr(choice.Code),
				Description: cloneStringPtr(choice.Description),
				Selectable:  choice.Selectable,
				Diagnostic:  choice.Diagnostic,
			}
		}
	}
	return cloned
}

type TwoPageEntryReferenceSnapshot struct {
	Original                     *sourceform.SourceParentProjection
	ProjectSource, WorkingSource int
	Zone, SubZone                vprocore.ProjectMetadataCell
	Fields                       []sourceform.SourceParentSharedReference
	Policies                     []TwoPageEntryFieldPolicy
	MasterEditingAvailable       bool
	ProjectChoices               *sourceform.SourceProjectChoices
	ProjectAssignmentAvailable   bool
	ProjectAssignmentDiagnostic  string
}

type TwoPageEntryReferenceSnapshotInternal = TwoPageEntryReferenceSnapshot

func ReadTwoPageEntryReferenceFields(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext,
	provider *TwoPageEntryReferenceProvider, contextID, form string, selection TwoPageEntryReferenceSelection,
	aliases TwoPageEntryReferenceAliases, zone, subZone vprocore.ProjectMetadataCell) ([]sourceform.SourceParentSharedReference, error) {
	return readTwoPageEntryReferenceFieldsWithHistoricalFilters(ctx, tx, owner, provider, contextID, form, selection,
		aliases, zone, subZone, false)
}

func readTwoPageEntryReferenceFieldsWithHistoricalFilters(ctx context.Context, tx *sql.Tx, owner *vprocore.SqliteContext,
	provider *TwoPageEntryReferenceProvider, contextID, form string, selection TwoPageEntryReferenceSelection,
	aliases TwoPageEntryReferenceAliases, zone, subZone vprocore.ProjectMetadataCell, historical bool) ([]sourceform.SourceParentSharedReference, error) {
	if tx == nil || owner == nil || provider == nil {
		return nil, errors.New("complete-entry references require the owned transaction and catalogue provider")
	}
	if err := vprocore.ProfileOwnedFiles(owner); err != nil {
		return nil, err
	}
	if err := verifyTwoPageEntryReferenceAliases(ctx, tx, owner, map[string]string{aliases.Project: "project", aliases.Lists: "VLists"}); err != nil {
		return nil, err
	}
	fields, err := twoPageEntryReferenceFields(form)
	if err != nil {
		return nil, err
	}
	if len(provider.Fields) != len(fields) {
		return nil, errors.New("complete-entry reference provider belongs to another source form")
	}
	for _, field := range fields {
		if expected, present := provider.Fields[field.Column]; !present || expected != field {
			return nil, errors.New("complete-entry reference provider changed its exact source policies")
		}
	}

	var cacheKey twoPageStaticRefCacheKey
	var stamp twoPageStaticVListsStamp
	var cachedStatic map[string]sourceform.SourceParentSharedReference
	cacheable := false
	if contextID != "" &&
		selection.ProjectSource >= 1 && selection.ProjectSource <= 2 &&
		selection.WorkingSource >= 1 && selection.WorkingSource <= 3 &&
		(aliases.Project == "project" || aliases.Project == "main") &&
		(aliases.Lists == "VLists" || aliases.Lists == "two_page_entry_refs") &&
		(aliases.Su == "" || aliases.Su == "su" || aliases.Su == "sivi_su" || aliases.Su == "main") {
		if readerPtrs, ok := twoPageStaticReadersKey(provider.Readers); ok {
			if st, ok := readTwoPageVListsStamp(ctx, tx, owner, aliases.Lists); ok {
				cacheKey = twoPageStaticRefCacheKey{
					owner:      owner,
					contextID:  contextID,
					form:       form,
					listsAlias: aliases.Lists,
					readers:    readerPtrs,
				}
				stamp = st
				cacheable = true
				cachedStatic, _ = twoPageStaticRefCache.get(cacheKey, stamp)
			}
		}
	}

	var freshStatic map[string]sourceform.SourceParentSharedReference
	if cacheable && cachedStatic == nil {
		freshStatic = make(map[string]sourceform.SourceParentSharedReference, len(fields))
	}

	result := make([]sourceform.SourceParentSharedReference, 0, len(fields))
	for _, field := range fields {
		if cachedStatic != nil && isTwoPageStaticReferenceField(field) {
			if cachedRef, ok := cachedStatic[field.Column]; ok {
				result = append(result, cloneSourceParentSharedReference(cachedRef))
				continue
			}
		}
		var reference sourceform.SourceParentSharedReference
		var err error
		if historical && (field.Column == "SubZone" || field.Column == "SiteSeries") {
			_, filterError := twoPageEntryBECFilter("Zone", zone, 4)
			if filterError == nil && field.Column == "SiteSeries" {
				_, filterError = twoPageEntryBECFilter("SubZone", subZone, 8)
			}
			if filterError != nil {
				result = append(result, sourceform.SourceParentSharedReference{Column: field.Column, ListName: field.List,
					Required: field.Required, Source: "owned historical BEC filters",
					Diagnostic:  "Historical BEC filter cannot query choices: " + filterError.Error(),
					Definitions: vprocore.ProjectMetadataTable{Columns: []vprocore.ProjectMetadataColumn{}, Rows: []vprocore.ProjectMetadataRow{}},
					Choices:     []sourceform.SourceParentSharedReferenceChoice{}})
				continue
			}
		}
		switch field.Reader {
		case "project", "master-unit", "working-unit":
			reference, err = ReadTwoPageEntryContextReference(ctx, tx, owner, contextID, form, selection, aliases, field)
		default:
			reference, err = provider.Read(ctx, tx, aliases.Lists, field, zone, subZone)
		}
		if err != nil {
			return nil, err
		}
		if freshStatic != nil && isTwoPageStaticReferenceField(field) {
			freshStatic[field.Column] = cloneSourceParentSharedReference(reference)
		}
		result = append(result, reference)
	}
	if err := vprocore.ProfileOwnedFiles(owner); err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if freshStatic != nil {
		twoPageStaticRefCache.put(cacheKey, stamp, freshStatic)
	}
	return result, nil
}

func ReadTwoPageEntryReferences(s *vprocore.ContextService, ctx context.Context, contextID, plot, form string,
	zone, subZone vprocore.ProjectMetadataCell, readers TwoPageEntryReferenceReaders) (*TwoPageEntryReferenceSnapshotInternal, error) {
	return ReadTwoPageEntryReferenceSnapshot(s, ctx, contextID, plot, form, readers,
		&TwoPageEntryReferenceFilters{zone, subZone})
}

func ReadTwoPageEntryReferenceSnapshot(s *vprocore.ContextService, ctx context.Context, contextID, plot, form string,
	readers TwoPageEntryReferenceReaders, filters *TwoPageEntryReferenceFilters) (*TwoPageEntryReferenceSnapshotInternal, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if filters != nil {
		if _, err := twoPageEntryBECFilter("Zone", filters.Zone, 4); err != nil {
			return nil, err
		}
		if _, err := twoPageEntryBECFilter("SubZone", filters.SubZone, 8); err != nil {
			return nil, err
		}
	}
	provider, err := NewTwoPageEntryReferenceProvider(form, readers)
	if err != nil {
		return nil, err
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (*TwoPageEntryReferenceSnapshotInternal, error) {
		return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*TwoPageEntryReferenceSnapshotInternal, error) {
			values, err := plots.Projects.Preferences.Snapshot()
			if err != nil {
				return nil, err
			}
			selection, err := TwoPageEntryReferenceSelectionFromConfig(values)
			if err != nil {
				return nil, err
			}
			tables, err := sourceform.ReadSourceParentTables(ctx, owner, tx, plot)
			if err != nil {
				return nil, err
			}
			original, err := ProjectTwoPageParent(ctx, contextID, owner.Selection.Project, plot, form, tables[0], tables[1])
			if err != nil {
				return nil, err
			}
			if len(original.Rows) != 1 {
				return nil, errors.New("complete-entry snapshot requires one owned physical source pair")
			}
			policies, err := TwoPageEntryFieldPolicies(form)
			if err != nil {
				return nil, err
			}
			var zone, subZone vprocore.ProjectMetadataCell
			if filters != nil {
				zone, subZone = filters.Zone, filters.SubZone
			} else {
				for _, binding := range original.Bindings {
					switch binding.Binding {
					case "Zone":
						zone = original.Rows[0].Env.Cells[binding.Column]
					case "SubZone":
						subZone = original.Rows[0].Env.Cells[binding.Column]
					}
				}
			}
			fields, err := readTwoPageEntryReferenceFieldsWithHistoricalFilters(ctx, tx, owner, provider, contextID, form, selection,
				TwoPageEntryReferenceAliases{"project", "VLists", "su"}, zone, subZone, filters == nil)
			if err != nil {
				return nil, err
			}
			choices, err := sourceform.ReadSourceProjectChoicesAtAlias(ctx, owner, tx, contextID, selection.ProjectSource, "project")
			if err != nil {
				return nil, err
			}
			available, diagnostic, err := sourceform.SourceProjectAssignmentAvailability(ctx, tx, selection.ProjectSource)
			if err != nil {
				return nil, err
			}
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			return &TwoPageEntryReferenceSnapshotInternal{Original: original, ProjectSource: selection.ProjectSource,
				WorkingSource: selection.WorkingSource, Zone: vprocore.CloneSiteUnitCell(zone), SubZone: vprocore.CloneSiteUnitCell(subZone),
				Fields: fields, Policies: policies, MasterEditingAvailable: vprocore.MasterBECAllowed(plots.CurrentUser),
				ProjectChoices: choices, ProjectAssignmentAvailable: available,
				ProjectAssignmentDiagnostic: diagnostic}, nil
		})
	})
}
