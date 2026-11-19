package projectops

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"hash"
	"math"
	"slices"
	"strings"

	"github.com/boostao/vpro/app/internal/sqlutil"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func writeDigestBytes(h hash.Hash, b []byte) {
	var lenBuf [8]byte
	binary.BigEndian.PutUint64(lenBuf[:], uint64(len(b)))
	_, _ = h.Write(lenBuf[:])
	_, _ = h.Write(b)
}

func writeDigestString(h hash.Hash, s string) {
	writeDigestBytes(h, []byte(s))
}

func writeDigestUint64(h hash.Hash, v uint64) {
	var buf [8]byte
	binary.BigEndian.PutUint64(buf[:], v)
	_, _ = h.Write(buf[:])
}

func hashLoadedProjectSnapshot(snap *loadedProjectSnapshot) string {
	if snap == nil {
		return ""
	}
	h := sha256.New()
	writeDigestString(h, snap.project)
	writeDigestString(h, snap.path)

	for _, suffix := range compareTableSuffixes {
		writeDigestString(h, suffix)
		cols := snap.columns[suffix]
		writeDigestUint64(h, uint64(len(cols)))
		for _, col := range cols {
			writeDigestString(h, col)
		}

		byPlot := snap.rawCells[suffix]
		plots := make([]string, 0, len(byPlot))
		for plot := range byPlot {
			plots = append(plots, plot)
		}
		slices.Sort(plots)
		writeDigestUint64(h, uint64(len(plots)))

		for _, plot := range plots {
			writeDigestString(h, plot)
			byKey := byPlot[plot]
			keys := make([]string, 0, len(byKey))
			for k := range byKey {
				keys = append(keys, k)
			}
			slices.Sort(keys)
			writeDigestUint64(h, uint64(len(keys)))

			for _, k := range keys {
				writeDigestString(h, k)
				rowMap := byKey[k]
				for _, col := range cols {
					cell := rowMap[col]
					writeDigestString(h, cell.storage)
					switch cell.storage {
					case "integer":
						writeDigestUint64(h, uint64(cell.intVal))
					case "real":
						writeDigestUint64(h, math.Float64bits(cell.realVal))
					case "text", "blob":
						writeDigestBytes(h, cell.bytes)
					}
				}
			}
		}
	}

	writeDigestString(h, "Metadata")
	writeDigestUint64(h, uint64(len(snap.metaColumns)))
	for _, col := range snap.metaColumns {
		writeDigestString(h, col)
	}
	metaKeys := make([]string, 0, len(snap.metaRaw))
	for k := range snap.metaRaw {
		metaKeys = append(metaKeys, k)
	}
	slices.Sort(metaKeys)
	writeDigestUint64(h, uint64(len(metaKeys)))
	for _, k := range metaKeys {
		writeDigestString(h, k)
		rowMap := snap.metaRaw[k]
		for _, col := range snap.metaColumns {
			cell := rowMap[col]
			writeDigestString(h, cell.storage)
			switch cell.storage {
			case "integer":
				writeDigestUint64(h, uint64(cell.intVal))
			case "real":
				writeDigestUint64(h, math.Float64bits(cell.realVal))
			case "text", "blob":
				writeDigestBytes(h, cell.bytes)
			}
		}
	}
	return hex.EncodeToString(h.Sum(nil))
}

func computeMergeSnapshotDigest(srcSnap, tgtSnap, baseSnap *loadedProjectSnapshot) string {
	h := sha256.New()
	writeDigestString(h, hashLoadedProjectSnapshot(srcSnap))
	writeDigestString(h, hashLoadedProjectSnapshot(tgtSnap))
	writeDigestString(h, hashLoadedProjectSnapshot(baseSnap))
	return hex.EncodeToString(h.Sum(nil))
}

func applyThreeWayMergeMetadata(
	ctx context.Context,
	tx *sql.Tx,
	auditStmt *sql.Stmt,
	tgtProj, actor, now string,
	srcSnap, tgtSnap *loadedProjectSnapshot,
	items []MergeConflictItem,
	resolveDecision func(MergeConflictItem) string,
	allocatedIDs *[]int64,
	reservedDeletedIDs *[]int64,
	auditRows *int,
) error {
	// Reconcile accepted <Target>_Metadata changes inside the same atomic transaction.
	metaTbl := vprocore.QuoteHeaderIdentifier(tgtProj + "_Metadata")
	for _, item := range items {
		if err := ctx.Err(); err != nil {
			return err
		}
		if resolveDecision(item) != MergeResolutionAcceptSource {
			continue
		}
		if item.Field == "*" {
			if item.SourceVal != nil && item.TargetVal == nil {
				sKey := item.srcRowKey
				if sKey == "" {
					sKey = item.Key
				}
				srcRow := srcSnap.metaRaw[sKey]
				cols := tgtSnap.metaColumns
				if len(cols) == 0 {
					cols = srcSnap.metaColumns
				}
				newMetaID, mErr := allocateSafeMetadataID(ctx, tx, tgtProj)
				if mErr != nil {
					return mErr
				}
				*allocatedIDs = append(*allocatedIDs, newMetaID)
				quotedCols := make([]string, len(cols))
				marks := make([]string, len(cols))
				args := make([]any, len(cols))
				for i, col := range cols {
					quotedCols[i] = vprocore.QuoteHeaderIdentifier(col)
					marks[i] = "?"
					if col == "ID" {
						args[i] = newMetaID
						continue
					}
					cell := srcRow[col]
					if err := validateMergedCell("Metadata", col, cell); err != nil {
						return fmt.Errorf("metadata %s.%s: %w", sKey, col, err)
					}
					args[i] = normalizeMergedParam("Metadata", col, cell)
				}
				insSQL := fmt.Sprintf("INSERT INTO %s (%s) VALUES (%s)", metaTbl, strings.Join(quotedCols, ", "), strings.Join(marks, ", "))
				if _, err := tx.ExecContext(ctx, insSQL, args...); err != nil {
					return err
				}
				for _, col := range cols {
					if col == "ID" {
						continue
					}
					c := srcRow[col]
					if c.storage == "null" {
						continue
					}
					if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, nil, "_Metadata", col, now, nil, auditTextForRawCell(c), newMetaID); err != nil {
						return err
					}
					*auditRows++
				}
			} else if item.SourceVal == nil && item.TargetVal != nil {
				tKey := item.tgtRowKey
				if tKey == "" {
					tKey = item.Key
				}
				tgtRow := tgtSnap.metaRaw[tKey]
				idCell := tgtRow["ID"]
				if idCell.storage != "integer" {
					return fmt.Errorf("cannot delete target Metadata row %s without integer ID", tKey)
				}
				if idCell.intVal > 0 {
					if err := reserveChildID(ctx, tx, tgtProj+"_Metadata", idCell.intVal); err != nil {
						return err
					}
					*reservedDeletedIDs = append(*reservedDeletedIDs, idCell.intVal)
				}
				dRes, dErr := tx.ExecContext(ctx, `DELETE FROM `+metaTbl+` WHERE "ID" = ?`, idCell.intVal)
				if dErr != nil {
					return dErr
				}
				if n, _ := dRes.RowsAffected(); n != 1 {
					return fmt.Errorf("merge metadata delete (ID %d) matched %d rows", idCell.intVal, n)
				}
				for _, col := range tgtSnap.metaColumns {
					if col == "ID" {
						continue
					}
					c := tgtRow[col]
					if c.storage == "null" {
						continue
					}
					if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, nil, "_Metadata", col, now, auditTextForRawCell(c), nil, idCell.intVal); err != nil {
						return err
					}
					*auditRows++
				}
			}
			continue
		}

		idx := strings.LastIndex(item.Key, ".")
		if idx <= 0 {
			return fmt.Errorf("malformed metadata diff key %q", item.Key)
		}
		rowKey := item.Key[:idx]
		sKey := item.srcRowKey
		if sKey == "" {
			sKey = rowKey
		}
		tKey := item.tgtRowKey
		if tKey == "" {
			tKey = rowKey
		}
		srcCell := srcSnap.metaRaw[sKey][item.Field]
		tgtRow := tgtSnap.metaRaw[tKey]
		idCell := tgtRow["ID"]
		if idCell.storage != "integer" {
			return fmt.Errorf("target Metadata row %s lacks integer ID", tKey)
		}
		if err := validateMergedCell("Metadata", item.Field, srcCell); err != nil {
			return fmt.Errorf("metadata %s.%s: %w", tKey, item.Field, err)
		}
		param := normalizeMergedParam("Metadata", item.Field, srcCell)
		uRes, uErr := tx.ExecContext(ctx, `UPDATE `+metaTbl+` SET `+vprocore.QuoteHeaderIdentifier(item.Field)+` = ? WHERE "ID" = ?`, param, idCell.intVal)
		if uErr != nil {
			return uErr
		}
		if n, _ := uRes.RowsAffected(); n != 1 {
			return fmt.Errorf("merge metadata update on %s (ID %d) matched %d rows", item.Field, idCell.intVal, n)
		}
		var beforeVal, afterVal any
		if item.TargetVal != nil {
			beforeVal = *item.TargetVal
		}
		if item.SourceVal != nil {
			afterVal = *item.SourceVal
		}
		if _, err := auditStmt.ExecContext(ctx, tgtProj, actor, nil, "_Metadata", item.Field, now, beforeVal, afterVal, idCell.intVal); err != nil {
			return err
		}
		*auditRows++
	}
	return nil
}

var mergedEnvTextMax = map[string]int{
	"PlotNumber": 7, "FieldNumber": 50, "ProjectID": 30, "FSRegionDistrict": 7,
	"Ecosection": 3, "NtsMapSheet": 8, "AirPhotoNum": 20,
	"Zone": 4, "SubZone": 8, "SiteSeries": 5, "RealmClass": 5, "MapUnit": 15,
	"SnowCoverregime": 1, "Exposure1": 2, "Exposure2": 2,
	"SiteDisturbance1": 8, "SiteDisturbance2": 8, "SiteDisturbance3": 8,
	"Photo": 50, "SoilSurveyor": 30, "VegSurveyor": 30,
	"BedrockGeology1": 4, "BedrockGeology2": 4, "BedrockGeology3": 4,
	"CoarseFragLith1": 12, "CoarseFragLith2": 12, "CoarseFragLith3": 12,
	"FloodingRegimeDur": 2, "FloodingRegimeFreq": 7,
	"GeoMorProSubSurf": 3, "GeoMorProSurf": 3,
	"HumusForm": 4, "HumusFormPhase": 50,
	"HydroGeoSubSystem": 2, "HydroGeoSystem": 3,
	"RootRestrictingType": 1, "RootZoneParticleSize": 6,
	"SoilDrainage": 5, "SoilClassGroup": 4, "SoilClassSubGroup": 4,
	"SurfaceExpSubSurf": 3, "SurfaceExpSurf": 3,
	"SurficialMaterialSubSurf": 6, "SurficialMaterialSurf": 6,
	"TerrainTextureSubSurf": 3, "TerrainTextureSurf": 3,
	"WaterSource": 5,
}

var mergedAdminTextMax = map[string]int{
	"Plot": 7, "PlotType": 10, "SitePlotQuality": 15, "VegPlotQuality": 15, "SoilPlotQuality": 15,
	"EnteredBy": 50, "UserSiteUnit": 100, "BECSiteUnit": 100,
}

var mergedEnvStrataCoverCols = []string{
	"StrataCoverTree", "StrataCoverShrub", "StrataCoverHerb", "StrataCoverMoss",
}

func validateMergedCell(suffix, col string, cell rawSQLiteCell) error {
	if cell.storage == "null" {
		return nil
	}
	if cell.storage == "text" {
		txt := string(cell.bytes)
		if err := sqlutil.ValidateUTF16Bound(suffix+"."+col, txt, 0); err != nil {
			return err
		}
		switch suffix {
		case "Env":
			if maxLen, ok := mergedEnvTextMax[col]; ok {
				return sqlutil.ValidateUTF16Bound("Env."+col, txt, maxLen)
			}
		case "Admin":
			if maxLen, ok := mergedAdminTextMax[col]; ok {
				return sqlutil.ValidateUTF16Bound("Admin."+col, txt, maxLen)
			}
		case "Veg":
			if maxLen, ok := vprocore.VegetationTextMaximum[col]; ok {
				return sqlutil.ValidateUTF16Bound("Veg."+col, txt, maxLen)
			}
		case "Humus", "Mineral":
			if maxLen, ok := vprocore.SoilChildTextMaximum[suffix][col]; ok && maxLen > 0 {
				return sqlutil.ValidateUTF16Bound(suffix+"."+col, txt, maxLen)
			}
		case "Other":
			if maxLen, ok := vprocore.OtherTextMaximum[col]; ok {
				return sqlutil.ValidateUTF16Bound("Other."+col, txt, maxLen)
			}
		}
	}
	isCoverCol := (suffix == "Veg" && slices.Contains(vegCoverCols, col)) ||
		(suffix == "Env" && slices.Contains(mergedEnvStrataCoverCols, col)) ||
		(suffix == "Admin" && col == "StrataCoverTotal")
	if isCoverCol && (cell.storage == "real" || cell.storage == "integer") {
		val := cell.realVal
		if cell.storage == "integer" {
			val = float64(cell.intVal)
		}
		if _, ok := sqlutil.NarrowSingleCover(val); !ok {
			return fmt.Errorf("cover %s.%s=%v must be from 0 to under 100%% (e.g. 99.9%%)", suffix, col, val)
		}
	}
	return nil
}

func normalizeMergedParam(suffix, col string, cell rawSQLiteCell) any {
	if cell.storage == "integer" {
		isBool := col == "Flag" ||
			(suffix == "Env" && (col == "SpeciesListComplete" || col == "SV_FloodPlain")) ||
			(suffix == "Admin" && col == "UpdatedFromCards") ||
			(suffix == "Other" && strings.HasPrefix(col, "UserFlag"))
		if isBool {
			if cell.intVal != 0 {
				return int64(-1)
			}
			return int64(0)
		}
	}
	return cell.sqlParam()
}
