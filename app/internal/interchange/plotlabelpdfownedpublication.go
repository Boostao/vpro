package interchange

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"fmt"
	"path/filepath"
	"reflect"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/vprocore"
)

type plotLabelPDFPublicationHooks struct {
	observe     func(string) error
	runtime     plotLabelPDFRuntime
	snapshot    vprocore.PublicationReadSnapshotHooks
	publication vprocore.ArtifactPublicationHooks
}

func snapshotPlotLabelPDFPreparation(expected ownedPlotLabelPDFPreparation) (ownedPlotLabelPDFPreparation, error) {
	for i, table := range expected.Source {
		table.Columns = slices.Clone(table.Columns)
		table.Rows = slices.Clone(table.Rows)
		for j, row := range table.Rows {
			row.Cells = slices.Clone(row.Cells)
			for k, cell := range row.Cells {
				row.Cells[k] = vprocore.CloneSiteUnitCell(cell)
			}
			table.Rows[j] = row
		}
		expected.Source[i] = table
	}
	header, err := plotLabelPDFHeader(expected.Source, expected.Preview.PlotNumber)
	if err != nil {
		return ownedPlotLabelPDFPreparation{}, err
	}
	if !reflect.DeepEqual(expected.Preview.Header, header) {
		return ownedPlotLabelPDFPreparation{}, errors.New("label PDF reviewed header disagrees with its complete physical source")
	}
	expected.Preview.Header = header
	expected.Bytes = bytes.Clone(expected.Bytes)
	return expected, nil
}

func PublishOwnedPlotLabelPDF(s *vprocore.ContextService, ctx context.Context, contextID string, expected ownedPlotLabelPDFPreparation, requested string, hooks plotLabelPDFPublicationHooks) (vprocore.ArtifactPublication, error) {
	expected, err := snapshotPlotLabelPDFPreparation(expected)
	if err != nil {
		return vprocore.ArtifactPublication{}, err
	}
	if !strings.EqualFold(filepath.Ext(requested), ".pdf") {
		return vprocore.ArtifactPublication{}, errors.New("label PDF publication requires an explicit .pdf destination")
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (result vprocore.ArtifactPublication, resultErr error) {
		owner := plots.Projects.Sqlite
		unlock, err := owner.AcquireMutex(ctx)
		if err != nil {
			return result, err
		}
		defer unlock()
		defer func() {
			if result.Published && resultErr != nil {
				resultErr = fmt.Errorf("owned label PDF published; do not replay publication: %w", resultErr)
			}
		}()
		if expected.Preview.ContextID != contextID || expected.Selection != owner.Selection {
			return result, errors.New("owned label PDF context/project/scope/path differs; reload review")
		}
		observe := func(phase string) error {
			if hooks.observe != nil {
				return hooks.observe(phase)
			}
			return nil
		}
		validate := func() error {
			actual, err := vprocore.WithPublicationReadSnapshot(ctx, owner, hooks.snapshot, func(tx *sql.Tx) (*ownedPlotLabelPDFPreparation, error) {
				return readPlotLabelPDFPreparationSnapshot(ctx, contextID, expected.Preview.PlotNumber, owner, tx, hooks.runtime)
			})
			if err != nil {
				return err
			}
			if !reflect.DeepEqual(*actual, expected) {
				return errors.New("owned label PDF physical source/schema/date/fonts/bytes differs; reload review")
			}
			return nil
		}
		if err := validate(); err != nil {
			return result, err
		}
		if err := observe("validated"); err != nil {
			return result, err
		}
		format := vprocore.ReviewedBytesPublicationFormat(
			"label PDF",
			"label PDF",
			"owned label PDF",
			".vpro-label-pdf-*.tmp",
			"label PDF differs from the internally prepared complete reviewed artifact",
			expected.Bytes,
		)
		result, resultErr = vprocore.PublishArtifactChecked(ctx, requested, format, func() error {
			if err := observe("precommit"); err != nil {
				return err
			}
			return validate()
		}, hooks.publication)
		if result.Published {
			resultErr = errors.Join(resultErr, observe("published"), validate())
		}
		return result, resultErr
	})
}
