package plotentry

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// MensurationService provides context-fenced FS882 4th-card mensuration
// operations over optional <Project>_TreePlot and <Project>_Trees tables.
type MensurationService struct {
	contexts *vprocore.ContextService
}

// NewMensurationService constructs a MensurationService bound to a ContextService owner.
func NewMensurationService(contexts *vprocore.ContextService) (*MensurationService, error) {
	if contexts == nil {
		return nil, errors.New("mensuration service requires a context service")
	}
	return &MensurationService{contexts: contexts}, nil
}

func (s *MensurationService) requireService(ctx context.Context) error {
	if s == nil || s.contexts == nil {
		return errors.New("mensuration service is unavailable")
	}
	if ctx == nil {
		return errors.New("mensuration operation requires a request context")
	}
	return ctx.Err()
}

func currentAuditActor(plots *vprocore.PlotService) (string, int) {
	plots.Mu.RLock()
	user, strength := plots.CurrentUser, plots.AuditStrength
	plots.Mu.RUnlock()
	if strings.TrimSpace(user) == "" {
		user = "User"
	}
	return user, strength
}

// GetPlotMensuration returns all <Project>_TreePlot and <Project>_Trees rows for plot.
// On projects without optional mensuration tables, it returns HasTables=false and empty slices.
func (s *MensurationService) GetPlotMensuration(ctx context.Context, contextID, plot string) (*vprocore.PlotMensurationData, error) {
	if err := s.requireService(ctx); err != nil {
		return nil, err
	}
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (*vprocore.PlotMensurationData, error) {
		owner := plots.Projects.Sqlite
		return vprocore.WithReadSnapshotValue(ctx, owner, func(tx *sql.Tx) (*vprocore.PlotMensurationData, error) {
			return vprocore.ReadPlotMensurationTx(ctx, tx, "project", owner.Selection.Project, plot, owner.ReadOnly)
		})
	})
}

// EnsureMensurationTables idempotently creates <Project>_TreePlot and <Project>_Trees (plus indexes
// and USysTreePlot/USysTrees temp views) inside an atomic BEGIN IMMEDIATE transaction.
func (s *MensurationService) EnsureMensurationTables(ctx context.Context, contextID string) (*vprocore.EnsureMensurationTablesResult, error) {
	if err := s.requireService(ctx); err != nil {
		return nil, err
	}
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (*vprocore.EnsureMensurationTablesResult, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return nil, err
		}
		owner := plots.Projects.Sqlite
		if owner.ReadOnly {
			return nil, vprocore.ErrReadOnlyContext
		}
		user, strength := currentAuditActor(plots)
		var (
			project         string
			createdTreePlot bool
			createdTrees    bool
		)
		if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
			project = wtx.Project
			var err error
			createdTreePlot, createdTrees, err = vprocore.EnsureMensurationTablesTx(ctx, wtx.Tx, wtx.Project)
			if err != nil {
				return err
			}
			if strength >= 2 && (createdTreePlot || createdTrees) {
				now := time.Now().Format("2006-01-02 15:04:05")
				field := "CreateTable"
				for _, item := range []struct {
					created bool
					table   string
				}{
					{createdTreePlot, "_" + vprocore.MensurationTreePlotSuffix},
					{createdTrees, "_" + vprocore.MensurationTreesSuffix},
				} {
					if !item.created {
						continue
					}
					if _, err := wtx.RecordAudit(ctx, vprocore.AuditWriteEntry{
						Project:   wtx.Project,
						User:      user,
						Table:     item.table,
						EditField: &field,
						EditWhen:  now,
						AfterEdit: "VP08",
					}); err != nil {
						return err
					}
				}
			}
			return nil
		}); err != nil {
			return nil, err
		}
		if err := owner.EnsureMensurationViews(ctx); err != nil {
			return nil, err
		}
		owner.InvalidateSchemaCache()
		return &vprocore.EnsureMensurationTablesResult{
			Project:         project,
			TreePlotTable:   project + "_" + vprocore.MensurationTreePlotSuffix,
			TreesTable:      project + "_" + vprocore.MensurationTreesSuffix,
			CreatedTreePlot: createdTreePlot,
			CreatedTrees:    createdTrees,
			HasTables:       true,
		}, nil
	})
}

// SaveTreePlot atomically inserts or updates one <Project>_TreePlot row with audit provenance.
func (s *MensurationService) SaveTreePlot(ctx context.Context, contextID string, record vprocore.TreePlotRecord) (*vprocore.TreePlotRecord, error) {
	if err := s.requireService(ctx); err != nil {
		return nil, err
	}
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (*vprocore.TreePlotRecord, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return nil, err
		}
		owner := plots.Projects.Sqlite
		if owner.ReadOnly {
			return nil, vprocore.ErrReadOnlyContext
		}
		user, strength := currentAuditActor(plots)
		var saved *vprocore.TreePlotRecord
		if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
			var err error
			saved, err = vprocore.SaveTreePlotInTx(ctx, wtx, user, strength, record)
			return err
		}); err != nil {
			return nil, err
		}
		return saved, nil
	})
}

// DeleteTreePlot atomically deletes one <Project>_TreePlot row by composite key with audit provenance.
func (s *MensurationService) DeleteTreePlot(ctx context.Context, contextID, plot, subPlot string, measurementID int) error {
	if err := s.requireService(ctx); err != nil {
		return err
	}
	_, err := vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return struct{}{}, err
		}
		owner := plots.Projects.Sqlite
		if owner.ReadOnly {
			return struct{}{}, vprocore.ErrReadOnlyContext
		}
		user, strength := currentAuditActor(plots)
		return struct{}{}, owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
			return vprocore.DeleteTreePlotInTx(ctx, wtx, user, strength, plot, subPlot, measurementID)
		})
	})
	return err
}

// SaveTreeRow atomically inserts or updates one <Project>_Trees row with audit provenance.
func (s *MensurationService) SaveTreeRow(ctx context.Context, contextID string, record vprocore.TreeRowRecord) (*vprocore.TreeRowRecord, error) {
	if err := s.requireService(ctx); err != nil {
		return nil, err
	}
	return vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (*vprocore.TreeRowRecord, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return nil, err
		}
		owner := plots.Projects.Sqlite
		if owner.ReadOnly {
			return nil, vprocore.ErrReadOnlyContext
		}
		user, strength := currentAuditActor(plots)
		var saved *vprocore.TreeRowRecord
		if err := owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
			var err error
			saved, err = vprocore.SaveTreeRowInTx(ctx, wtx, user, strength, record)
			return err
		}); err != nil {
			return nil, err
		}
		return saved, nil
	})
}

// DeleteTreeRow atomically deletes matching <Project>_Trees row(s) with audit provenance.
func (s *MensurationService) DeleteTreeRow(ctx context.Context, contextID, plot, subPlot string, measurementID, treeNum int) error {
	if err := s.requireService(ctx); err != nil {
		return err
	}
	_, err := vprocore.WithContextPlotRequest(ctx, s.contexts, contextID, func(plots *vprocore.PlotService) (struct{}, error) {
		if err := plots.RequireContextEdit(); err != nil {
			return struct{}{}, err
		}
		owner := plots.Projects.Sqlite
		if owner.ReadOnly {
			return struct{}{}, vprocore.ErrReadOnlyContext
		}
		user, strength := currentAuditActor(plots)
		return struct{}{}, owner.WithImmediateWriteTx(ctx, func(wtx *vprocore.WriteTx) error {
			return vprocore.DeleteTreeRowInTx(ctx, wtx, user, strength, plot, subPlot, measurementID, treeNum)
		})
	})
	return err
}
