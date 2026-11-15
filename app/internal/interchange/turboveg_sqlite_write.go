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
			_ = os.Remove(tmpPath)
		}
	}()
	_ = tmpFile.Close()

	db, err := sql.Open("sqlite3", sqlutil.SqliteFileURI(tmpPath, "rw")+"&_journal_mode=DELETE&_synchronous=FULL&_foreign_keys=on")
	if err != nil {
		return "", "", err
	}
	db.SetMaxOpenConns(1)

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		db.Close()
		return "", "", err
	}

	build := func() error {
		if _, err := tx.ExecContext(ctx, `PRAGMA foreign_keys = ON`); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, turboVeg3OfficialDDL); err != nil {
			return fmt.Errorf("create official Turboveg 3 schema: %w", err)
		}

		projName := truncateUTF16Units(strings.TrimSpace(ds.ProjectName), 50)
		if projName == "" {
			projName = "VProExport"
		}

		if _, err := tx.ExecContext(ctx, `
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
		`); err != nil {
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
		if _, err := tx.ExecContext(ctx, `INSERT INTO projectdatasets (projectid, datasetid) VALUES (1, 1)`); err != nil {
			return err
		}

		vlStmt, err := tx.PrepareContext(ctx, `INSERT INTO vegetationlayers (id, name, abbreviation, description) VALUES (?, ?, ?, ?)`)
		if err != nil {
			return err
		}
		for _, vl := range canonicalTV3VegetationLayers {
			if _, err := vlStmt.ExecContext(ctx, vl.ID, vl.Name, vl.Abbreviation, vl.Description); err != nil {
				vlStmt.Close()
				return err
			}
		}
		vlStmt.Close()

		fStmt, err := tx.PrepareContext(ctx, `
			INSERT INTO fields (
				id, fielddomainid, fieldgroupid, lookuptableid, unitid,
				fieldname, fieldtype, description, datatypeid, width, decimals, mandatory, readonly
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`)
		if err != nil {
			return err
		}
		pdStmt, err := tx.PrepareContext(ctx, `
			INSERT INTO profiledata (id, profileid, fieldid, "order", "show", mandatory, readonly)
			VALUES (?, 1, ?, ?, 1, ?, 0)`)
		if err != nil {
			fStmt.Close()
			return err
		}
		pdID := 1
		for _, f := range canonicalTV3Fields {
			if _, err := fStmt.ExecContext(ctx,
				f.ID, f.DomainID, f.GroupID, f.LookupTableID, f.UnitID,
				f.Name, f.FieldType, f.Description, f.DataTypeID, f.Width, f.Decimals, f.Mandatory,
			); err != nil {
				pdStmt.Close()
				fStmt.Close()
				return err
			}
			if f.DomainID == 1 {
				if _, err := pdStmt.ExecContext(ctx, pdID, f.ID, pdID, f.Mandatory); err != nil {
					pdStmt.Close()
					fStmt.Close()
					return err
				}
				pdID++
			}
		}
		pdStmt.Close()
		fStmt.Close()

		// Seed taxa
		taxaStmt, err := tx.PrepareContext(ctx, `
			INSERT INTO taxa (
				id, taxonlistid, taxongroupid, taxonrankid, scientificname,
				vernacularname, author, tv2speciesid, tv2validid, lettercode, issynonym, metadata
			) VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)`)
		if err != nil {
			return err
		}
		taxonIDByNR := make(map[int]int, len(ds.Species))
		for _, sp := range ds.Species {
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
				taxaStmt.Close()
				return err
			}
			taxonIDByNR[sp.SpeciesNR] = sp.SpeciesNR
		}
		taxaStmt.Close()

		// Collect and seed distinct covercodes under lookupdataid = 1 ('00' Percentage (%))
		coverMeanByKey := map[string]float64{"0": 0}
		for _, pb := range ds.Plots {
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
			return err
		}
		coverCodeIDByKey := make(map[string]int, len(coverKeys))
		for idx, key := range coverKeys {
			ccID := idx + 1
			mean := coverMeanByKey[key]
			if _, err := ccStmt.ExecContext(ctx, ccID, key, mean, mean, mean); err != nil {
				ccStmt.Close()
				return err
			}
			coverCodeIDByKey[key] = ccID
		}
		ccStmt.Close()

		locStmt, err := tx.PrepareContext(ctx, `INSERT INTO locations (id, the_geom) VALUES (?, ?)`)
		if err != nil {
			return err
		}
		defer locStmt.Close()

		plotStmt, err := tx.PrepareContext(ctx, `INSERT INTO plots (id, datasetid, locationid, metadata) VALUES (?, 1, ?, ?)`)
		if err != nil {
			return err
		}
		defer plotStmt.Close()

		poStmt, err := tx.PrepareContext(ctx, `
			INSERT INTO plotobservations (
				id, plotid, guid, changedby, changedwhen, quality, deleted, synoptic, nrofplotobservations, accessregime
			) VALUES (?, ?, ?, 'VPro', ?, 3, 0, 0, NULL, 0)`)
		if err != nil {
			return err
		}
		defer poStmt.Close()

		hdrStmt, err := tx.PrepareContext(ctx, `
			INSERT INTO plotobservationheaderdata (
				id, plotobservationid, fieldid, lookupdataid, valuestring, valueinteger, valuefloat, deleted
			) VALUES (?, ?, ?, ?, ?, ?, ?, 0)`)
		if err != nil {
			return err
		}
		defer hdrStmt.Close()

		soStmt, err := tx.PrepareContext(ctx, `
			INSERT INTO speciesobservations (
				id, plotobservationid, taxonid, vegetationlayerid, covercodeid, originaltaxonconcept, metadata, deleted
			) VALUES (?, ?, ?, ?, ?, ?, ?, 0)`)
		if err != nil {
			return err
		}
		defer soStmt.Close()

		sodStmt, err := tx.PrepareContext(ctx, `
			INSERT INTO speciesobservationdata (
				id, speciesobservationid, fieldid, lookupdataid, valuestring, valueinteger, valuefloat, deleted
			) VALUES (?, ?, ?, NULL, ?, NULL, ?, 0)`)
		if err != nil {
			return err
		}
		defer sodStmt.Close()

		nowDelphi := timeToDelphiDateTime(time.Now())
		nextLocID := 1
		nextHdrID := 1
		nextSOID := 1
		nextSODID := 1

		addStrHdr := func(poID, fieldID int, val string) error {
			if strings.TrimSpace(val) == "" {
				return nil
			}
			_, err := hdrStmt.ExecContext(ctx, nextHdrID, poID, fieldID, nil, val, nil, nil)
			nextHdrID++
			return err
		}
		addIntHdr := func(poID, fieldID int, val *int) error {
			if val == nil {
				return nil
			}
			_, err := hdrStmt.ExecContext(ctx, nextHdrID, poID, fieldID, nil, nil, *val, nil)
			nextHdrID++
			return err
		}
		addFloatHdr := func(poID, fieldID int, val *float64) error {
			if val == nil {
				return nil
			}
			_, err := hdrStmt.ExecContext(ctx, nextHdrID, poID, fieldID, nil, nil, nil, *val)
			nextHdrID++
			return err
		}

		for idx, pb := range ds.Plots {
			if idx%128 == 0 {
				runtime.Gosched()
				if err := ctx.Err(); err != nil {
					return err
				}
			}
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
				if _, err := locStmt.ExecContext(ctx, nextLocID, wkt); err != nil {
					return err
				}
				locIDAny = nextLocID
				nextLocID++
			}
			plotMeta, _ := json.Marshal(map[string]string{"vpro_plot": h.PlotNumber})
			if _, err := plotStmt.ExecContext(ctx, plotID, locIDAny, string(plotMeta)); err != nil {
				return err
			}
			if _, err := poStmt.ExecContext(ctx, plotID, plotID, guid, nowDelphi); err != nil {
				return err
			}

			releveNR := plotID
			if err := addIntHdr(plotID, tv3FieldReleveNR, &releveNR); err != nil {
				return err
			}
			// Country CA (lookupdataid=2) and Coverscale 00 (lookupdataid=1)
			if _, err := hdrStmt.ExecContext(ctx, nextHdrID, plotID, tv3FieldCountry, 2, "CA", nil, nil); err != nil {
				return err
			}
			nextHdrID++
			if _, err := hdrStmt.ExecContext(ctx, nextHdrID, plotID, tv3FieldCoverscale, 1, "00", nil, nil); err != nil {
				return err
			}
			nextHdrID++

			if strings.TrimSpace(h.Date) != "" {
				if dFloat, exactISO, ok := parseISODateToDelphi(h.Date); ok {
					var rawStrAny any
					if !exactISO {
						rawStrAny = h.Date
					}
					if _, err := hdrStmt.ExecContext(ctx, nextHdrID, plotID, tv3FieldDate, nil, rawStrAny, nil, dFloat); err != nil {
						return err
					}
				} else {
					if _, err := hdrStmt.ExecContext(ctx, nextHdrID, plotID, tv3FieldDate, nil, h.Date, nil, nil); err != nil {
						return err
					}
				}
				nextHdrID++
			}

			for _, fOp := range []error{
				addFloatHdr(plotID, tv3FieldSurfArea, h.PlotSize),
				addIntHdr(plotID, tv3FieldAltitude, h.Elevation),
				addIntHdr(plotID, tv3FieldExposition, h.Aspect),
				addFloatHdr(plotID, tv3FieldInclinatio, h.Slope),
				addStrHdr(plotID, tv3FieldAuthor, h.Surveyor),
				addFloatHdr(plotID, tv3FieldLatitude, h.Latitude),
				addFloatHdr(plotID, tv3FieldLongitude, h.Longitude),
				addStrHdr(plotID, tv3FieldVProPlot, h.PlotNumber),
				addStrHdr(plotID, tv3FieldFieldNR, h.FieldNumber),
				addStrHdr(plotID, tv3FieldProjectID, h.ProjectID),
				addStrHdr(plotID, tv3FieldZone, h.Zone),
				addStrHdr(plotID, tv3FieldSubzone, h.SubZone),
				addStrHdr(plotID, tv3FieldSiteSeries, h.SiteSeries),
				addStrHdr(plotID, tv3FieldSiteUnit, h.SiteUnit),
				addStrHdr(plotID, tv3FieldMoisture, h.MoistureRegime),
				addStrHdr(plotID, tv3FieldNutrient, h.NutrientRegime),
				addStrHdr(plotID, tv3FieldMesoSlope, h.MesoSlopePosition),
				addStrHdr(plotID, tv3FieldSurfShape, h.SurfaceShape),
				addStrHdr(plotID, tv3FieldDrainage, h.SoilDrainage),
				addStrHdr(plotID, tv3FieldHumusForm, h.HumusForm),
				addStrHdr(plotID, tv3FieldLocation, h.Location),
				addStrHdr(plotID, tv3FieldSiteNotes, h.SiteNotes),
				addStrHdr(plotID, tv3FieldVegNotes, h.VegNotes),
				addStrHdr(plotID, tv3FieldSoilNotes, h.SoilNotes),
			} {
				if fOp != nil {
					return fOp
				}
			}

			// Count (taxonid, vegetationlayerid) multiplicity in this plot to guarantee observationsspecies_index02 uniqueness.
			type taxLayerKey struct {
				taxonID int
				layerID int
			}
			multiplicity := map[taxLayerKey]int{}
			for _, o := range pb.Observations {
				multiplicity[taxLayerKey{taxonIDByNR[o.SpeciesNR], o.TVLayerID}]++
			}
			usedConceptKey := map[string]int{}

			for _, o := range pb.Observations {
				taxonID := taxonIDByNR[o.SpeciesNR]
				tvLayerID := o.TVLayerID
				if tvLayerID < 0 || tvLayerID > 10 {
					tvLayerID = 6
				}
				ccID := coverCodeIDByKey[formatCoverCodeKey(o.Cover)]
				baseConcept := strings.TrimSpace(o.SciName)
				if baseConcept == "" {
					baseConcept = o.SpeciesCode
				}
				cw, hasCW := vproSublayerCodeToTV[o.VProLayer]
				concept := baseConcept
				if multiplicity[taxLayerKey{taxonID, tvLayerID}] > 1 || (hasCW && !cw.IsPrimary) {
					if strings.TrimSpace(o.VProLayer) != "" {
						concept = baseConcept + " [" + o.VProLayer + "]"
					}
				}
				uniqProbe := fmt.Sprintf("%d|%d|%s", taxonID, tvLayerID, concept)
				usedConceptKey[uniqProbe]++
				if n := usedConceptKey[uniqProbe]; n > 1 {
					concept = fmt.Sprintf("%s #%d", concept, n)
				}

				soMeta, _ := json.Marshal(map[string]string{
					"vpro_code":  o.SpeciesCode,
					"vpro_layer": o.VProLayer,
				})
				soID := nextSOID
				nextSOID++
				if _, err := soStmt.ExecContext(ctx, soID, plotID, taxonID, tvLayerID, ccID, concept, string(soMeta)); err != nil {
					return err
				}

				if strings.TrimSpace(o.SpeciesCode) != "" {
					if _, err := sodStmt.ExecContext(ctx, nextSODID, soID, tv3FieldSppVProCode, o.SpeciesCode, nil); err != nil {
						return err
					}
					nextSODID++
				}
				if strings.TrimSpace(o.VProLayer) != "" {
					if _, err := sodStmt.ExecContext(ctx, nextSODID, soID, tv3FieldSppVProLay, o.VProLayer, nil); err != nil {
						return err
					}
					nextSODID++
				}
				if o.Height != nil {
					if _, err := sodStmt.ExecContext(ctx, nextSODID, soID, tv3FieldSppHeight, nil, *o.Height); err != nil {
						return err
					}
					nextSODID++
				}
				if strings.TrimSpace(o.Collected) != "" {
					if _, err := sodStmt.ExecContext(ctx, nextSODID, soID, tv3FieldSppCollect, o.Collected, nil); err != nil {
						return err
					}
					nextSODID++
				}
			}
		}

		// Self-verify zero foreign key violations before committing.
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

	if err := build(); err != nil {
		_ = tx.Rollback()
		_ = db.Close()
		return "", "", err
	}
	if err := tx.Commit(); err != nil {
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
