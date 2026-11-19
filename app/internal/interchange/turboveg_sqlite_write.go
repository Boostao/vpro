package interchange

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"time"

	"github.com/boostao/vpro/app/internal/sqlutil"
)

type tv3PlotSQLiteWriter struct {
	ctx              context.Context
	locStmt          *sql.Stmt
	plotStmt         *sql.Stmt
	poStmt           *sql.Stmt
	hdrStmt          *sql.Stmt
	soStmt           *sql.Stmt
	sodStmt          *sql.Stmt
	taxonIDByNR      map[int]int
	coverCodeIDByKey map[string]int
	nowDelphi        float64
	nextLocID        int
	nextHdrID        int
	nextSOID         int
	nextSODID        int
}

func writeTurboVeg3SQLite(ctx context.Context, destinationPath string, ds tvDataset) (string, string, error) {
	absDest, err := filepath.Abs(filepath.Clean(destinationPath))
	if err != nil {
		return "", "", err
	}
	if err := os.MkdirAll(filepath.Dir(absDest), 0o755); err != nil {
		return "", "", err
	}
	tmpFile, err := os.CreateTemp(filepath.Dir(absDest), ".vpro-tv3-*.sqlite")
	if err != nil {
		return "", "", err
	}
	tmpPath := tmpFile.Name()
	published := false
	defer func() {
		if !published {
			_ = sqlutil.RemoveSQLiteWithSidecars(tmpPath)
		}
	}()
	_ = tmpFile.Close()

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(tmpPath, "rw")+"&_journal_mode=DELETE&_synchronous=FULL&_foreign_keys=on")
	if err != nil {
		return "", "", err
	}
	db.SetMaxOpenConns(1)

	tx, err := sqlutil.BeginStagedTx(ctx, db)
	if err != nil {
		db.Close()
		return "", "", err
	}

	if err := buildTV3SQLiteTx(ctx, tx, ds); err != nil {
		_ = tx.Rollback()
		_ = db.Close()
		return "", "", err
	}
	if err := sqlutil.CommitStagedTx(ctx, tx); err != nil {
		_ = db.Close()
		return "", "", err
	}
	if err := db.Close(); err != nil {
		return "", "", err
	}
	if err := os.Rename(tmpPath, absDest); err != nil {
		return "", "", err
	}
	published = true

	rawBytes, err := os.ReadFile(absDest)
	if err != nil {
		return "", "", err
	}
	sum := sha256.Sum256(rawBytes)
	return absDest, hex.EncodeToString(sum[:]), nil
}

func buildTV3SQLiteTx(ctx context.Context, tx *sql.Tx, ds tvDataset) error {
	if _, err := tx.ExecContext(ctx, `PRAGMA foreign_keys = ON`); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, turboVeg3OfficialDDL); err != nil {
		return fmt.Errorf("create official Turboveg 3 schema: %w", err)
	}
	if err := seedTV3ReferenceMetadata(ctx, tx, ds.ProjectName); err != nil {
		return err
	}
	if err := seedTV3LayersAndFields(ctx, tx); err != nil {
		return err
	}
	taxonIDByNR, err := seedTV3Taxa(ctx, tx, ds.Species)
	if err != nil {
		return err
	}
	coverCodeIDByKey, err := seedTV3CoverCodes(ctx, tx, ds.Plots)
	if err != nil {
		return err
	}
	if err := writeTV3PlotsAndObservations(ctx, tx, ds.Plots, taxonIDByNR, coverCodeIDByKey); err != nil {
		return err
	}
	return verifyTV3ForeignKeys(ctx, tx)
}

const tv3ReferenceSeedSQL = `
	INSERT INTO datatypes (id, name) VALUES
		(1, 'TEXT'), (2, 'INTEGER'), (3, 'REAL'), (4, 'DATE'), (5, 'BOOLEAN');
	INSERT INTO units (id, name, desciption) VALUES
		(1, '%', 'Percentage'),
		(2, 'm', 'Meters'),
		(3, 'deg', 'Degrees'),
		(4, 'm2', 'Square meters');
	INSERT INTO fielddomains (id, name) VALUES
		(1, 'Administrative and header data'),
		(2, 'Species attributes'),
		(3, 'Species trait data');
	INSERT INTO fieldgroups (id, name, "order") VALUES
		(1, 'General', 1),
		(2, 'Location & Topography', 2),
		(3, 'BEC Classification & Edaphics', 3),
		(4, 'Notes', 4);
	INSERT INTO lookuptables (id, filename, description) VALUES
		(1, 'tvscale', 'Cover abundance scales'),
		(2, 'country', 'Countries');
	INSERT INTO lookupcaptions (id, lookuptableid, columnno, caption) VALUES
		(1, 1, 1, 'Scale code'),
		(2, 1, 2, 'Description'),
		(3, 2, 1, 'Country code'),
		(4, 2, 2, 'Country');
	INSERT INTO lookupdata (id, lookuptableid, code, description1, description2, description3, description4) VALUES
		(1, 1, '00', 'Percentage (%)', '', '', ''),
		(2, 2, 'CA', 'Canada', '', '', '');
	INSERT INTO custodians (id, name, institution) VALUES
		(1, 'B.C. Ministry of Forests BEC Program', 'Province of British Columbia, Research Branch');
	INSERT INTO datasetgroups (id, name) VALUES (1, 'Core');
	INSERT INTO profiles (id, name) VALUES (1, 'VPro_BEC_Standard');
	INSERT INTO taxonlists (id, name) VALUES (1, 'BCPlantTaxonomy');
	INSERT INTO taxongroups (id, name) VALUES
		(1, 'Vascular plants'),
		(2, 'Stoneworts'),
		(3, 'Mosses'),
		(4, 'Lichens'),
		(5, 'Mushrooms'),
		(6, 'Algae');
	INSERT INTO taxonranks (id, name) VALUES
		(1, 'Genus'),
		(2, 'Species'),
		(3, 'Subspecies'),
		(4, 'Variety');
	INSERT INTO metadata ("key", "value") VALUES
		('dbversion', '3.9'),
		('generator', 'VPro (B.C. Ministry of Forests BEC Program)');
`

func seedTV3ReferenceMetadata(ctx context.Context, tx *sql.Tx, rawProjectName string) error {
	projName := truncateUTF16Units(strings.TrimSpace(rawProjectName), 50)
	if projName == "" {
		projName = "VProExport"
	}
	if _, err := tx.ExecContext(ctx, tv3ReferenceSeedSQL); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO projects (id, name) VALUES (1, ?)`, projName); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `
		INSERT INTO datasets (id, name, datasetgroupid, profileid, taxonlistid, custodianid, guid)
		VALUES (1, ?, 1, 1, 1, 1, ?)`, projName, newTurboVegUUID()); err != nil {
		return err
	}
	_, err := tx.ExecContext(ctx, `INSERT INTO projectdatasets (projectid, datasetid) VALUES (1, 1)`)
	return err
}

func seedTV3LayersAndFields(ctx context.Context, tx *sql.Tx) error {
	vlStmt, err := tx.PrepareContext(ctx, `INSERT INTO vegetationlayers (id, name, abbreviation, description) VALUES (?, ?, ?, ?)`)
	if err != nil {
		return err
	}
	defer vlStmt.Close()
	for _, vl := range canonicalTV3VegetationLayers {
		if _, err := vlStmt.ExecContext(ctx, vl.ID, vl.Name, vl.Abbreviation, vl.Description); err != nil {
			return err
		}
	}

	fStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO fields (
			id, fielddomainid, fieldgroupid, lookuptableid, unitid,
			fieldname, fieldtype, description, datatypeid, width, decimals, mandatory, readonly
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`)
	if err != nil {
		return err
	}
	defer fStmt.Close()

	pdStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO profiledata (id, profileid, fieldid, "order", "show", mandatory, readonly)
		VALUES (?, 1, ?, ?, 1, ?, 0)`)
	if err != nil {
		return err
	}
	defer pdStmt.Close()

	pdID := 1
	for _, f := range canonicalTV3Fields {
		if _, err := fStmt.ExecContext(ctx,
			f.ID, f.DomainID, f.GroupID, f.LookupTableID, f.UnitID,
			f.Name, f.FieldType, f.Description, f.DataTypeID, f.Width, f.Decimals, f.Mandatory,
		); err != nil {
			return err
		}
		if f.DomainID == 1 {
			if _, err := pdStmt.ExecContext(ctx, pdID, f.ID, pdID, f.Mandatory); err != nil {
				return err
			}
			pdID++
		}
	}
	return nil
}

func seedTV3Taxa(ctx context.Context, tx *sql.Tx, species []tvSpeciesItem) (map[int]int, error) {
	taxaStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO taxa (
			id, taxonlistid, taxongroupid, taxonrankid, scientificname,
			vernacularname, author, tv2speciesid, tv2validid, lettercode, issynonym, metadata
		) VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)`)
	if err != nil {
		return nil, err
	}
	defer taxaStmt.Close()

	taxonIDByNR := make(map[int]int, len(species))
	for _, sp := range species {
		sci := strings.TrimSpace(sp.ScientificName)
		if sci == "" {
			sci = sp.SpeciesCode
		}
		letter := truncateUTF16Units(strings.TrimSpace(sp.LetterCode), 7)
		if letter == "" {
			letter = truncateUTF16Units(strings.TrimSpace(sp.SpeciesCode), 7)
		}
		metaBytes, _ := json.Marshal(map[string]any{
			"vpro_code": sp.SpeciesCode,
			"lifeform":  sp.Lifeform,
		})
		if _, err := taxaStmt.ExecContext(ctx,
			sp.SpeciesNR,
			taxonGroupForLifeform(sp.Lifeform),
			taxonRankForSciName(sci),
			sci,
			nullEmpty(sp.EnglishName),
			nullEmpty(sp.Authority),
			sp.SpeciesNR,
			sp.SpeciesNR,
			nullEmpty(letter),
			string(metaBytes),
		); err != nil {
			return nil, err
		}
		taxonIDByNR[sp.SpeciesNR] = sp.SpeciesNR
	}
	return taxonIDByNR, nil
}

func seedTV3CoverCodes(ctx context.Context, tx *sql.Tx, plots []tvExportPlot) (map[string]int, error) {
	coverMeanByKey := map[string]float64{"0": 0}
	for _, pb := range plots {
		for _, o := range pb.Observations {
			key := formatCoverCodeKey(o.Cover)
			if _, exists := coverMeanByKey[key]; !exists {
				coverMeanByKey[key] = o.Cover
			}
		}
	}
	coverKeys := make([]string, 0, len(coverMeanByKey))
	for k := range coverMeanByKey {
		coverKeys = append(coverKeys, k)
	}
	slices.SortFunc(coverKeys, func(a, b string) int {
		va, vb := coverMeanByKey[a], coverMeanByKey[b]
		if va < vb {
			return -1
		}
		if va > vb {
			return 1
		}
		return strings.Compare(a, b)
	})

	ccStmt, err := tx.PrepareContext(ctx, `
		INSERT INTO covercodes (id, lookupdataid, code, percentage_mean, percentage_min, percentage_max)
		VALUES (?, 1, ?, ?, ?, ?)`)
	if err != nil {
		return nil, err
	}
	defer ccStmt.Close()

	coverCodeIDByKey := make(map[string]int, len(coverKeys))
	for idx, key := range coverKeys {
		ccID := idx + 1
		mean := coverMeanByKey[key]
		if _, err := ccStmt.ExecContext(ctx, ccID, key, mean, mean, mean); err != nil {
			return nil, err
		}
		coverCodeIDByKey[key] = ccID
	}
	return coverCodeIDByKey, nil
}

func writeTV3PlotsAndObservations(
	ctx context.Context,
	tx *sql.Tx,
	plots []tvExportPlot,
	taxonIDByNR map[int]int,
	coverCodeIDByKey map[string]int,
) error {
	w, closeStmts, err := prepareTV3PlotWriter(ctx, tx, taxonIDByNR, coverCodeIDByKey)
	if err != nil {
		return err
	}
	defer closeStmts()

	for idx, pb := range plots {
		if idx%128 == 0 {
			runtime.Gosched()
			if err := ctx.Err(); err != nil {
				return err
			}
		}
		if err := w.writePlotBundle(idx, pb); err != nil {
			return err
		}
	}
	return nil
}

func prepareTV3PlotWriter(
	ctx context.Context,
	tx *sql.Tx,
	taxonIDByNR map[int]int,
	coverCodeIDByKey map[string]int,
) (*tv3PlotSQLiteWriter, func(), error) {
	var opened []*sql.Stmt
	closeAll := func() {
		for _, st := range opened {
			_ = st.Close()
		}
	}
	prep := func(query string) (*sql.Stmt, error) {
		st, err := tx.PrepareContext(ctx, query)
		if err != nil {
			closeAll()
			return nil, err
		}
		opened = append(opened, st)
		return st, nil
	}

	locStmt, err := prep(`INSERT INTO locations (id, the_geom) VALUES (?, ?)`)
	if err != nil {
		return nil, nil, err
	}
	plotStmt, err := prep(`INSERT INTO plots (id, datasetid, locationid, metadata) VALUES (?, 1, ?, ?)`)
	if err != nil {
		return nil, nil, err
	}
	poStmt, err := prep(`
		INSERT INTO plotobservations (
			id, plotid, guid, changedby, changedwhen, quality, deleted, synoptic, nrofplotobservations, accessregime
		) VALUES (?, ?, ?, 'VPro', ?, 3, 0, 0, NULL, 0)`)
	if err != nil {
		return nil, nil, err
	}
	hdrStmt, err := prep(`
		INSERT INTO plotobservationheaderdata (
			id, plotobservationid, fieldid, lookupdataid, valuestring, valueinteger, valuefloat, deleted
		) VALUES (?, ?, ?, ?, ?, ?, ?, 0)`)
	if err != nil {
		return nil, nil, err
	}
	soStmt, err := prep(`
		INSERT INTO speciesobservations (
			id, plotobservationid, taxonid, vegetationlayerid, covercodeid, originaltaxonconcept, metadata, deleted
		) VALUES (?, ?, ?, ?, ?, ?, ?, 0)`)
	if err != nil {
		return nil, nil, err
	}
	sodStmt, err := prep(`
		INSERT INTO speciesobservationdata (
			id, speciesobservationid, fieldid, lookupdataid, valuestring, valueinteger, valuefloat, deleted
		) VALUES (?, ?, ?, NULL, ?, NULL, ?, 0)`)
	if err != nil {
		return nil, nil, err
	}

	return &tv3PlotSQLiteWriter{
		ctx:              ctx,
		locStmt:          locStmt,
		plotStmt:         plotStmt,
		poStmt:           poStmt,
		hdrStmt:          hdrStmt,
		soStmt:           soStmt,
		sodStmt:          sodStmt,
		taxonIDByNR:      taxonIDByNR,
		coverCodeIDByKey: coverCodeIDByKey,
		nowDelphi:        timeToDelphiDateTime(time.Now()),
		nextLocID:        1,
		nextHdrID:        1,
		nextSOID:         1,
		nextSODID:        1,
	}, closeAll, nil
}

func (w *tv3PlotSQLiteWriter) writePlotBundle(idx int, pb tvExportPlot) error {
	h := pb.Header
	plotID := h.PlotID
	if plotID <= 0 {
		plotID = idx + 1
	}
	guid := strings.TrimSpace(h.GUID)
	if guid == "" {
		guid = newTurboVegUUID()
	}

	var locIDAny any
	if h.Latitude != nil && h.Longitude != nil {
		wkt := formatWKTPoint(*h.Longitude, *h.Latitude)
		if _, err := w.locStmt.ExecContext(w.ctx, w.nextLocID, wkt); err != nil {
			return err
		}
		locIDAny = w.nextLocID
		w.nextLocID++
	}
	plotMeta, _ := json.Marshal(map[string]string{"vpro_plot": h.PlotNumber})
	if _, err := w.plotStmt.ExecContext(w.ctx, plotID, locIDAny, string(plotMeta)); err != nil {
		return err
	}
	if _, err := w.poStmt.ExecContext(w.ctx, plotID, plotID, guid, w.nowDelphi); err != nil {
		return err
	}
	if err := w.writePlotHeaders(plotID, h); err != nil {
		return err
	}
	return w.writePlotSpeciesObservations(plotID, pb.Observations)
}

func (w *tv3PlotSQLiteWriter) addStrHdr(poID, fieldID int, val string) error {
	if strings.TrimSpace(val) == "" {
		return nil
	}
	_, err := w.hdrStmt.ExecContext(w.ctx, w.nextHdrID, poID, fieldID, nil, val, nil, nil)
	w.nextHdrID++
	return err
}

func (w *tv3PlotSQLiteWriter) addIntHdr(poID, fieldID int, val *int) error {
	if val == nil {
		return nil
	}
	_, err := w.hdrStmt.ExecContext(w.ctx, w.nextHdrID, poID, fieldID, nil, nil, *val, nil)
	w.nextHdrID++
	return err
}

func (w *tv3PlotSQLiteWriter) addFloatHdr(poID, fieldID int, val *float64) error {
	if val == nil {
		return nil
	}
	_, err := w.hdrStmt.ExecContext(w.ctx, w.nextHdrID, poID, fieldID, nil, nil, nil, *val)
	w.nextHdrID++
	return err
}

func (w *tv3PlotSQLiteWriter) writePlotHeaders(plotID int, h tvPlotHeader) error {
	releveNR := plotID
	if err := w.addIntHdr(plotID, tv3FieldReleveNR, &releveNR); err != nil {
		return err
	}
	// Country CA (lookupdataid=2) and Coverscale 00 (lookupdataid=1)
	if _, err := w.hdrStmt.ExecContext(w.ctx, w.nextHdrID, plotID, tv3FieldCountry, 2, "CA", nil, nil); err != nil {
		return err
	}
	w.nextHdrID++
	if _, err := w.hdrStmt.ExecContext(w.ctx, w.nextHdrID, plotID, tv3FieldCoverscale, 1, "00", nil, nil); err != nil {
		return err
	}
	w.nextHdrID++

	if err := w.writePlotDateHeader(plotID, h.Date); err != nil {
		return err
	}
	return w.writePlotScalarHeaders(plotID, h)
}

func (w *tv3PlotSQLiteWriter) writePlotDateHeader(plotID int, rawDate string) error {
	if strings.TrimSpace(rawDate) == "" {
		return nil
	}
	if dFloat, exactISO, ok := parseISODateToDelphi(rawDate); ok {
		var rawStrAny any
		if !exactISO {
			rawStrAny = rawDate
		}
		if _, err := w.hdrStmt.ExecContext(w.ctx, w.nextHdrID, plotID, tv3FieldDate, nil, rawStrAny, nil, dFloat); err != nil {
			return err
		}
	} else if _, err := w.hdrStmt.ExecContext(w.ctx, w.nextHdrID, plotID, tv3FieldDate, nil, rawDate, nil, nil); err != nil {
		return err
	}
	w.nextHdrID++
	return nil
}

func (w *tv3PlotSQLiteWriter) writePlotScalarHeaders(plotID int, h tvPlotHeader) error {
	for _, fOp := range []error{
		w.addFloatHdr(plotID, tv3FieldSurfArea, h.PlotSize),
		w.addIntHdr(plotID, tv3FieldAltitude, h.Elevation),
		w.addIntHdr(plotID, tv3FieldExposition, h.Aspect),
		w.addFloatHdr(plotID, tv3FieldInclinatio, h.Slope),
		w.addStrHdr(plotID, tv3FieldAuthor, h.Surveyor),
		w.addFloatHdr(plotID, tv3FieldLatitude, h.Latitude),
		w.addFloatHdr(plotID, tv3FieldLongitude, h.Longitude),
		w.addStrHdr(plotID, tv3FieldVProPlot, h.PlotNumber),
		w.addStrHdr(plotID, tv3FieldFieldNR, h.FieldNumber),
		w.addStrHdr(plotID, tv3FieldProjectID, h.ProjectID),
		w.addStrHdr(plotID, tv3FieldZone, h.Zone),
		w.addStrHdr(plotID, tv3FieldSubzone, h.SubZone),
		w.addStrHdr(plotID, tv3FieldSiteSeries, h.SiteSeries),
		w.addStrHdr(plotID, tv3FieldSiteUnit, h.SiteUnit),
		w.addStrHdr(plotID, tv3FieldMoisture, h.MoistureRegime),
		w.addStrHdr(plotID, tv3FieldNutrient, h.NutrientRegime),
		w.addStrHdr(plotID, tv3FieldMesoSlope, h.MesoSlopePosition),
		w.addStrHdr(plotID, tv3FieldSurfShape, h.SurfaceShape),
		w.addStrHdr(plotID, tv3FieldDrainage, h.SoilDrainage),
		w.addStrHdr(plotID, tv3FieldHumusForm, h.HumusForm),
		w.addStrHdr(plotID, tv3FieldLocation, h.Location),
		w.addStrHdr(plotID, tv3FieldSiteNotes, h.SiteNotes),
		w.addStrHdr(plotID, tv3FieldVegNotes, h.VegNotes),
		w.addStrHdr(plotID, tv3FieldSoilNotes, h.SoilNotes),
	} {
		if fOp != nil {
			return fOp
		}
	}
	return nil
}

type tv3TaxonLayerKey struct {
	taxonID int
	layerID int
}

func (w *tv3PlotSQLiteWriter) writePlotSpeciesObservations(plotID int, observations []tvExportObs) error {
	// Count (taxonid, vegetationlayerid) multiplicity in this plot to guarantee observationsspecies_index02 uniqueness.
	multiplicity := map[tv3TaxonLayerKey]int{}
	for _, o := range observations {
		multiplicity[tv3TaxonLayerKey{w.taxonIDByNR[o.SpeciesNR], o.TVLayerID}]++
	}
	usedConceptKey := map[string]int{}

	for _, o := range observations {
		taxonID := w.taxonIDByNR[o.SpeciesNR]
		tvLayerID := o.TVLayerID
		if tvLayerID < 0 || tvLayerID > 10 {
			tvLayerID = 6
		}
		ccID := w.coverCodeIDByKey[formatCoverCodeKey(o.Cover)]
		concept := resolveUniqueTV3TaxonConcept(o, taxonID, tvLayerID, multiplicity, usedConceptKey)

		soMeta, _ := json.Marshal(map[string]string{
			"vpro_code":  o.SpeciesCode,
			"vpro_layer": o.VProLayer,
		})
		soID := w.nextSOID
		w.nextSOID++
		if _, err := w.soStmt.ExecContext(w.ctx, soID, plotID, taxonID, tvLayerID, ccID, concept, string(soMeta)); err != nil {
			return err
		}
		if err := w.writeSpeciesObservationAttributes(soID, o); err != nil {
			return err
		}
	}
	return nil
}

func resolveUniqueTV3TaxonConcept(
	o tvExportObs,
	taxonID, tvLayerID int,
	multiplicity map[tv3TaxonLayerKey]int,
	usedConceptKey map[string]int,
) string {
	baseConcept := strings.TrimSpace(o.SciName)
	if baseConcept == "" {
		baseConcept = o.SpeciesCode
	}
	cw, hasCW := vproSublayerCodeToTV[o.VProLayer]
	concept := baseConcept
	if multiplicity[tv3TaxonLayerKey{taxonID, tvLayerID}] > 1 || (hasCW && !cw.IsPrimary) {
		if strings.TrimSpace(o.VProLayer) != "" {
			concept = baseConcept + " [" + o.VProLayer + "]"
		}
	}
	uniqProbe := fmt.Sprintf("%d|%d|%s", taxonID, tvLayerID, concept)
	usedConceptKey[uniqProbe]++
	if n := usedConceptKey[uniqProbe]; n > 1 {
		concept = fmt.Sprintf("%s #%d", concept, n)
	}
	return concept
}

func (w *tv3PlotSQLiteWriter) writeSpeciesObservationAttributes(soID int, o tvExportObs) error {
	if strings.TrimSpace(o.SpeciesCode) != "" {
		if _, err := w.sodStmt.ExecContext(w.ctx, w.nextSODID, soID, tv3FieldSppVProCode, o.SpeciesCode, nil); err != nil {
			return err
		}
		w.nextSODID++
	}
	if strings.TrimSpace(o.VProLayer) != "" {
		if _, err := w.sodStmt.ExecContext(w.ctx, w.nextSODID, soID, tv3FieldSppVProLay, o.VProLayer, nil); err != nil {
			return err
		}
		w.nextSODID++
	}
	if o.Height != nil {
		if _, err := w.sodStmt.ExecContext(w.ctx, w.nextSODID, soID, tv3FieldSppHeight, nil, *o.Height); err != nil {
			return err
		}
		w.nextSODID++
	}
	if strings.TrimSpace(o.Collected) != "" {
		if _, err := w.sodStmt.ExecContext(w.ctx, w.nextSODID, soID, tv3FieldSppCollect, o.Collected, nil); err != nil {
			return err
		}
		w.nextSODID++
	}
	return nil
}

func verifyTV3ForeignKeys(ctx context.Context, tx *sql.Tx) error {
	fkRows, err := tx.QueryContext(ctx, `PRAGMA foreign_key_check`)
	if err != nil {
		return err
	}
	hasViolation := fkRows.Next()
	_ = fkRows.Close()
	if hasViolation {
		return errors.New("exported Turboveg 3 SQLite database failed PRAGMA foreign_key_check")
	}
	return nil
}
