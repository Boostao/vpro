package vprocore

import (
	"database/sql"
	"errors"
	"fmt"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

// PlotBundle batches the plot header, capabilities, Master BEC policy, and all non-audit
// child tables (Vegetation, Humus, Mineral, Other) from one read-only SQLite WAL snapshot.
// Audit entries are intentionally omitted so the Audit Trail tab can lazy-load on demand.
type PlotBundle struct {
	Header             *FS882Header                `json:"header"`
	HeaderCapabilities map[string]bool             `json:"headerCapabilities,omitempty"`
	CanEditMasterBEC   bool                        `json:"canEditMasterBEC"`
	ChildCapabilities  map[string]map[string]bool  `json:"childCapabilities,omitempty"`
	Vegetation         *VegetationReadAvailability `json:"vegetation"`
	Humus              []HumusRecord               `json:"humus"`
	HumusError         string                      `json:"humusError,omitempty"`
	Mineral            []MineralRecord             `json:"mineral"`
	MineralError       string                      `json:"mineralError,omitempty"`
	Other              []OtherRecord               `json:"other"`
}

// GetPlotBundle reads Header, Veg, Humus, Mineral, and Other inside a single read-only
// transaction on ProjectReadDB, preserving historical NULL-ID error isolation and exact
// plot-not-found semantics.
func (s *PlotService) GetPlotBundle(plotNumber string, includeCapabilities bool) (*PlotBundle, error) {
	ctx := s.OperationContext()
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	db, project, release, err := s.GetActiveReadDB()
	if err != nil {
		return nil, err
	}
	defer release()

	tx, err := db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	reader := sqlutil.ContextPlotDB{DB: tx, Ctx: ctx}

	headerCaps, err := s.headerCapabilities(reader, project)
	if err != nil {
		return nil, err
	}
	header, err := ReadHeader(reader, project, plotNumber, headerCaps)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("plot %q not found", plotNumber)
	}
	if err != nil {
		return nil, err
	}

	vegColCaps, err := s.childCapabilities(reader, project, "Veg")
	if err != nil {
		return nil, err
	}
	humusColCaps, err := s.childCapabilities(reader, project, "Humus")
	if err != nil {
		return nil, err
	}
	mineralColCaps, err := s.childCapabilities(reader, project, "Mineral")
	if err != nil {
		return nil, err
	}
	otherColCaps, err := s.childCapabilities(reader, project, "Other")
	if err != nil {
		return nil, err
	}

	vegRecords, vegErr := queryChildRecords[VegRecord](reader, project, "Veg", plotNumber, vegColCaps)
	vegetation, err := buildVegetationReadAvailability(vegRecords, vegErr)
	if err != nil {
		return nil, err
	}

	var humusError string
	humusRecords, err := queryChildRecords[HumusRecord](reader, project, "Humus", plotNumber, humusColCaps)
	if err != nil {
		var identity *childNullIdentityError
		if !errors.As(err, &identity) || identity.kind != "Humus" {
			return nil, err
		}
		humusRecords = nil
		humusError = identity.Error()
	}

	var mineralError string
	mineralRecords, err := queryChildRecords[MineralRecord](reader, project, "Mineral", plotNumber, mineralColCaps)
	if err != nil {
		var identity *childNullIdentityError
		if !errors.As(err, &identity) || identity.kind != "Mineral" {
			return nil, err
		}
		mineralRecords = nil
		mineralError = identity.Error()
	}

	otherRecords, err := queryChildRecords[OtherRecord](reader, project, "Other", plotNumber, otherColCaps)
	if err != nil {
		return nil, err
	}

	bundle := &PlotBundle{
		Header:           header,
		CanEditMasterBEC: s.CanEditMasterBEC(),
		Vegetation:       vegetation,
		Humus:            humusRecords,
		HumusError:       humusError,
		Mineral:          mineralRecords,
		MineralError:     mineralError,
		Other:            otherRecords,
	}

	if includeCapabilities {
		bundle.HeaderCapabilities = headerCaps
		vegDTOCaps, err := childDTOCapabilities("Veg", vegColCaps)
		if err != nil {
			return nil, err
		}
		humusDTOCaps, err := childDTOCapabilities("Humus", humusColCaps)
		if err != nil {
			return nil, err
		}
		mineralDTOCaps, err := childDTOCapabilities("Mineral", mineralColCaps)
		if err != nil {
			return nil, err
		}
		otherDTOCaps, err := childDTOCapabilities("Other", otherColCaps)
		if err != nil {
			return nil, err
		}
		bundle.ChildCapabilities = map[string]map[string]bool{
			"Veg":     vegDTOCaps,
			"Humus":   humusDTOCaps,
			"Mineral": mineralDTOCaps,
			"Other":   otherDTOCaps,
		}
	}

	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return bundle, nil
}
