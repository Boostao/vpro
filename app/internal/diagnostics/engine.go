package diagnostics

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

type synthesisValidatedOptions struct {
	sigBasis         string
	coverPrec        string
	unitSourceUsed   string
	suTableName      string
	suWritable       bool
	suReadOnlyReason string
}

func validateSynthesisOptions(owner *vprocore.SqliteContext, opts SynthesisOptions) (synthesisValidatedOptions, error) {
	sigBasis := strings.ToLower(strings.TrimSpace(opts.SignificanceBasis))
	if sigBasis == "" {
		sigBasis = "all_plots"
	}
	if sigBasis != "all_plots" && sigBasis != "present_plots" {
		return synthesisValidatedOptions{}, fmt.Errorf("unsupported significanceBasis %q; expected 'all_plots' or 'present_plots'", opts.SignificanceBasis)
	}
	coverPrec := strings.ToLower(strings.TrimSpace(opts.CoverPrecedence))
	if coverPrec == "" {
		coverPrec = "sublayer_sum"
	}
	if coverPrec != "sublayer_sum" && coverPrec != "strata_totals" {
		return synthesisValidatedOptions{}, fmt.Errorf("unsupported coverPrecedence %q; expected 'sublayer_sum' or 'strata_totals'", opts.CoverPrecedence)
	}
	if opts.OutlierThreshold < 0 || opts.OutlierThreshold > 1 {
		return synthesisValidatedOptions{}, fmt.Errorf("unsupported outlierThreshold %v; expected [0, 1]", opts.OutlierThreshold)
	}

	requestedSource := strings.ToLower(strings.TrimSpace(opts.UnitSource))
	if requestedSource == "" {
		requestedSource = "auto"
	}
	if requestedSource != "auto" && requestedSource != "su" && requestedSource != "user_site_unit" {
		return synthesisValidatedOptions{}, fmt.Errorf("unsupported unitSource %q; expected 'auto', 'su', or 'user_site_unit'", opts.UnitSource)
	}

	hasActiveSU := owner.Selection.SU != "" && !strings.EqualFold(owner.Selection.SU, "None")
	if requestedSource == "su" && !hasActiveSU {
		return synthesisValidatedOptions{}, errors.New("unitSource 'su' requires an active Site Unit (SU) table")
	}
	unitSourceUsed := "user_site_unit"
	suTableName := ""
	if hasActiveSU && (requestedSource == "auto" || requestedSource == "su") {
		unitSourceUsed = "su"
		suTableName = owner.Selection.SU + "_SU"
	}

	suWritable := false
	suReadOnlyReason := ""
	if unitSourceUsed == "su" {
		if _, _, wErr := validateWritableSUTarget(owner); wErr == nil {
			suWritable = true
		} else {
			suReadOnlyReason = wErr.Error()
		}
	} else {
		suReadOnlyReason = "Select an active Site Unit (SU) table to enable live plot reassignment"
	}

	return synthesisValidatedOptions{
		sigBasis:         sigBasis,
		coverPrec:        coverPrec,
		unitSourceUsed:   unitSourceUsed,
		suTableName:      suTableName,
		suWritable:       suWritable,
		suReadOnlyReason: suReadOnlyReason,
	}, nil
}

func readSUUnitAssignments(ctx context.Context, tx *sql.Tx, suTableName string) (map[string]string, []string, error) {
	suRawUnits := map[string]string{}
	var suPlotKeys []string
	seenSUKey := map[string]struct{}{}
	suRows, err := tx.QueryContext(ctx,
		`SELECT CAST("PlotNumber" AS TEXT), COALESCE(CAST("SiteUnit" AS TEXT), '')
		 FROM "su".`+vprocore.QuoteHeaderIdentifier(suTableName)+
			` WHERE typeof("PlotNumber")='text' ORDER BY rowid ASC`)
	if err != nil {
		return nil, nil, err
	}
	for suRows.Next() {
		var p, u string
		if err := suRows.Scan(&p, &u); err != nil {
			suRows.Close()
			return nil, nil, err
		}
		suRawUnits[p] = strings.TrimSpace(u)
		if _, seen := seenSUKey[p]; !seen {
			seenSUKey[p] = struct{}{}
			suPlotKeys = append(suPlotKeys, p)
		}
	}
	if err := errors.Join(suRows.Err(), suRows.Close()); err != nil {
		return nil, nil, err
	}
	return suRawUnits, suPlotKeys, nil
}

type partitionedSynthesisPlots struct {
	excludedUnits         []ExcludedUnitSummary
	excludedPlotCount     int
	unassignedPlots       []SynthesisUnitPlot
	classifiedPlots       []classifiedPlotRecord
	classifiedIndexByPlot map[string]int
	orderedUnits          []string
}

func partitionAndOrderSynthesisPlots(
	opts SynthesisOptions,
	unitSourceUsed string,
	orderedProjectPlots []SynthesisUnitPlot,
	suPlotKeys []string,
	suUnitsByPlotIdx []string,
) partitionedSynthesisPlots {
	// 4. Filter excluded units (.support / .poor / .nudum + custom patterns) and partition plots
	excludedMap := map[string]*ExcludedUnitSummary{}
	excludedPlotCount := 0
	unassignedCap := 0
	classifiedCap := len(orderedProjectPlots)
	if unitSourceUsed == "su" {
		classifiedCap = min(len(suPlotKeys), len(orderedProjectPlots))
		unassignedCap = max(0, len(orderedProjectPlots)-classifiedCap)
	}
	unassignedPlots := make([]SynthesisUnitPlot, 0, unassignedCap)
	classifiedPlots := make([]classifiedPlotRecord, 0, classifiedCap)
	classifiedIndexByPlot := make(map[string]int, classifiedCap)
	unitSet := map[string]bool{}

	for i := range orderedProjectPlots {
		info := orderedProjectPlots[i]
		var unitCode string
		if unitSourceUsed == "su" {
			unitCode = suUnitsByPlotIdx[i]
		} else {
			unitCode = strings.TrimSpace(info.UserSiteUnit)
		}
		if unitCode == "" {
			unassignedPlots = append(unassignedPlots, info)
			continue
		}
		if excluded, matched := MatchUnitExcluded(unitCode, opts.ExcludeStandardModifiers, opts.ExcludePatterns); excluded {
			excludedPlotCount++
			ex := excludedMap[unitCode]
			if ex == nil {
				ex = &ExcludedUnitSummary{
					SiteUnit:       unitCode,
					MatchedPattern: matched,
				}
				excludedMap[unitCode] = ex
			}
			ex.PlotCount++
			continue
		}
		unitSet[unitCode] = true
		classifiedIndexByPlot[info.PlotNumber] = len(classifiedPlots)
		classifiedPlots = append(classifiedPlots, classifiedPlotRecord{
			plotNumber:     info.PlotNumber,
			fieldNumber:    info.FieldNumber,
			siteUnit:       unitCode,
			zone:           info.Zone,
			subZone:        info.SubZone,
			siteSeries:     info.SiteSeries,
			userSiteUnit:   info.UserSiteUnit,
			moistureRegime: info.MoistureRegime,
			nutrientRegime: info.NutrientRegime,
			speciesCovers:  map[string]float64{},
		})
	}

	excludedUnits := make([]ExcludedUnitSummary, 0, len(excludedMap))
	for _, ex := range excludedMap {
		excludedUnits = append(excludedUnits, *ex)
	}
	slices.SortFunc(excludedUnits, func(a, b ExcludedUnitSummary) int {
		return strings.Compare(strings.ToLower(a.SiteUnit), strings.ToLower(b.SiteUnit))
	})

	// Order SiteUnits deterministically (explicit UnitOrder first, then Access PIVOT case-insensitive alphabetical)
	orderedUnits := make([]string, 0, len(unitSet))
	placedUnit := map[string]bool{}
	for _, u := range opts.UnitOrder {
		trimmed := strings.TrimSpace(u)
		if unitSet[trimmed] && !placedUnit[trimmed] {
			placedUnit[trimmed] = true
			orderedUnits = append(orderedUnits, trimmed)
		}
	}
	remUnits := make([]string, 0, len(unitSet))
	for u := range unitSet {
		if !placedUnit[u] {
			remUnits = append(remUnits, u)
		}
	}
	slices.SortFunc(remUnits, func(a, b string) int {
		if cmp := strings.Compare(strings.ToLower(a), strings.ToLower(b)); cmp != 0 {
			return cmp
		}
		return strings.Compare(a, b)
	})
	orderedUnits = append(orderedUnits, remUnits...)

	return partitionedSynthesisPlots{
		excludedUnits:         excludedUnits,
		excludedPlotCount:     excludedPlotCount,
		unassignedPlots:       unassignedPlots,
		classifiedPlots:       classifiedPlots,
		classifiedIndexByPlot: classifiedIndexByPlot,
		orderedUnits:          orderedUnits,
	}
}

func computeSnapshotInReadTx(
	ctx context.Context,
	tx *sql.Tx,
	owner *vprocore.SqliteContext,
	contextID string,
	opts SynthesisOptions,
	preTxStamp dbFileStamp,
	preTxOK bool,
) (*SynthesisSnapshot, error) {
	started := time.Now()
	project := owner.Selection.Project

	cfg, err := validateSynthesisOptions(owner, opts)
	if err != nil {
		return nil, err
	}

	// 1. Load optional Lump mapping
	lumpMap, lumpTableUsed, err := loadActiveLumpMap(ctx, tx, owner, opts.LumpTable, opts.LumpDBPath)
	if err != nil {
		return nil, err
	}

	// 2 & 3. Read scoped <SU>_SU and ordered <Project>_Env + <Project>_Admin headers (live file + WAL stamp cached)
	var suRawUnits map[string]string
	var suPlotKeys []string
	if cfg.unitSourceUsed == "su" {
		suRawUnits, suPlotKeys, err = readSUUnitAssignments(ctx, tx, cfg.suTableName)
		if err != nil {
			return nil, err
		}
	}

	orderedProjectPlots, projectPlotIdx, err := loadOrderedProjectPlots(ctx, tx, owner, project, preTxStamp, preTxOK)
	if err != nil {
		return nil, err
	}

	var suUnitsByPlotIdx []string
	if cfg.unitSourceUsed == "su" && len(orderedProjectPlots) > 0 {
		suUnitsByPlotIdx = make([]string, len(orderedProjectPlots))
		for _, p := range suPlotKeys {
			if idx, ok := projectPlotIdx[p]; ok {
				suUnitsByPlotIdx[idx] = suRawUnits[p]
			}
		}
	}

	part := partitionAndOrderSynthesisPlots(opts, cfg.unitSourceUsed, orderedProjectPlots, suPlotKeys, suUnitsByPlotIdx)

	// 5. Read unit long names from MasterSiteUnitList & UserSiteUnitList (cached by support DB file stamp)
	unitLongNames := loadUnitLongNamesForOwner(ctx, tx, owner)

	vegRes, err := loadAndFoldProjectVeg(ctx, tx, project, cfg.coverPrec, lumpMap, part.classifiedPlots, part.classifiedIndexByPlot)
	if err != nil {
		return nil, err
	}

	acc := accumulateUnitPlotsAndCovers(part.orderedUnits, part.classifiedPlots, vegRes.plotSpeciesTotals)

	matrixRes, err := buildSynthesisSpeciesAndUnits(
		ctx, tx, owner, opts, cfg.sigBasis,
		part.orderedUnits, unitLongNames, acc,
		vegRes.allSpeciesSet, vegRes.lumpSourcesByTarget,
	)
	if err != nil {
		return nil, err
	}

	// 9. Pairwise Similarity Matrix + BEC do_pairwise comparisons
	simMatrix, pairwiseComps := ComputePairwiseAnalysis(
		part.orderedUnits,
		acc.unitPlotCounts,
		matrixRes.speciesMeta,
		matrixRes.unitSpeciesStats,
		opts.Pairwise,
	)

	// 10. Candidate Misplaced Plots (Leave-One-Out Outlier Queue)
	outlierQueue := ComputeOutlierQueueWithThreshold(
		part.orderedUnits,
		part.classifiedPlots,
		acc.unitCoverSums,
		acc.unitTotalSums,
		acc.unitPlotCounts,
		opts.OutlierThreshold,
	)

	// 11. Relative Edatopic Grids (rSMR 0..8 x rSNR A..F)
	overallEdatopic, unitEdatopic := ComputeEdatopicGrids(part.orderedUnits, part.classifiedPlots)

	// 12. Synthesis Undo status
	canUndo, undoDepth, latestUndo := readSynthesisUndoStatus(ctx, tx, owner.Selection.SU)

	elapsedMs := float64(time.Since(started).Microseconds()) / 1000.0

	totalProjPlots := len(orderedProjectPlots)
	unassignedCount := len(part.unassignedPlots)

	return &SynthesisSnapshot{
		ContextID:           contextID,
		Project:             project,
		SU:                  owner.Selection.SU,
		SUTableName:         cfg.suTableName,
		UnitSourceUsed:      cfg.unitSourceUsed,
		SUWritable:          cfg.suWritable,
		SUReadOnlyReason:    cfg.suReadOnlyReason,
		LumpTableUsed:       lumpTableUsed,
		LumpFoldedTaxa:      len(vegRes.foldedSourceTaxa),
		LumpCappedCells:     vegRes.lumpCappedCells,
		SignificanceBasis:   cfg.sigBasis,
		TotalProjectPlots:   totalProjPlots,
		ClassifiedPlotCount: len(part.classifiedPlots),
		UnassignedPlotCount: unassignedCount,
		ExcludedPlotCount:   part.excludedPlotCount,
		ComputeMs:           RoundACE15(elapsedMs, 2),
		ExcludedUnits:       part.excludedUnits,
		UnassignedPlots:     part.unassignedPlots,
		Units:               matrixRes.unitsOut,
		Species:             matrixRes.speciesRows,
		SimilarityMatrix:    simMatrix,
		PairwiseComparisons: pairwiseComps,
		OutlierQueue:        outlierQueue,
		OverallEdatopicGrid: overallEdatopic,
		UnitEdatopicGrids:   unitEdatopic,
		CanUndo:             canUndo,
		UndoDepth:           undoDepth,
		LatestUndo:          latestUndo,
	}, nil
}

func computeSnapshotForPlots(
	ctx context.Context,
	owner *vprocore.SqliteContext,
	contextID string,
	opts SynthesisOptions,
) (_ *SynthesisSnapshot, resultErr error) {
	if err := sqlutil.AcquireMutexLease(ctx, &owner.Mu); err != nil {
		return nil, err
	}
	defer owner.Mu.Unlock()
	if err := vprocore.ProfileOwnedFiles(owner); err != nil {
		return nil, err
	}
	preTxStamp, preTxOK := statDBFileWithWAL(owner.Selection.ProjectPath)
	tx, err := owner.BeginReadSnapshot(ctx)
	if err != nil {
		return nil, err
	}
	defer func() {
		if rb := tx.Rollback(); rb != nil && !errors.Is(rb, sql.ErrTxDone) {
			resultErr = errors.Join(resultErr, rb)
		}
	}()

	snap, err := computeSnapshotInReadTx(ctx, tx, owner, contextID, opts, preTxStamp, preTxOK)
	if err != nil {
		return nil, err
	}
	if err := vprocore.ProfileOwnedFiles(owner); err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return snap, nil
}

// ComputeSynthesisSnapshot computes the complete reactive BEC differential, pairwise similarity,
// Leave-One-Out outlier queue, and 9x6 edatopic grid snapshot for the active context.
func ComputeSynthesisSnapshot(
	ctx context.Context,
	contexts *vprocore.ContextService,
	contextID string,
	opts SynthesisOptions,
) (*SynthesisSnapshot, error) {
	if ctx == nil {
		return nil, errors.New("synthesis snapshot requires a request context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if contexts == nil {
		return nil, errors.New("classification context service is unavailable")
	}
	return vprocore.WithContextPlotRequest(ctx, contexts, contextID, func(plots *vprocore.PlotService) (*SynthesisSnapshot, error) {
		return computeSnapshotForPlots(ctx, plots.Projects.Sqlite, contextID, opts)
	})
}
