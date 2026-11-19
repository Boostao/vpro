package vprocore

import (
	"context"
	"errors"
	"fmt"
	"math"
	"strconv"
)

type PlotLocationRow struct {
	EnvRowID         string                `json:"envRowId"`
	AdminRowID       string                `json:"adminRowId"`
	MembershipRowIDs []string              `json:"membershipRowIds"`
	StoredLongitude  ProjectMetadataCell   `json:"storedLongitude"`
	Values           []ProjectMetadataCell `json:"values"`
}

type PlotLocationReport struct {
	Project string                   `json:"project"`
	SU      string                   `json:"su"`
	Fields  []EnvironmentReportField `json:"fields"`
	Rows    []PlotLocationRow        `json:"rows"`
}

func PlotLocationFields() []EnvironmentReportField {
	return []EnvironmentReportField{
		{"Env", "PlotNumber", "Plot Number", false},
		{"Env", "Zone", "Zone", false},
		{"Env", "SubZone", "Subzone", false},
		{"Env", "SiteSeries", "Site Series", false},
		{"Env", "LocationAccuracy", "Accuracy", false},
		{"Env", "Latitude", "Latitude", false},
		{"Env", "Longitude", "Longitude", false},
		{"Env", "Elevation", "Elevation", false},
	}
}

const (
	// WesternBCMinLat..WesternBCMaxLon define the unified Western Canada / Alaska / BC
	// bounding box used identically across vprocore, spatial geodesy, and GeoPackage export.
	WesternBCMinLat = 45.0
	WesternBCMaxLat = 85.0
	WesternBCMinLon = -170.0
	WesternBCMaxLon = -100.0
)

// NormalizeWesternBCCoordinates normalizes positive Western Hemisphere longitudes (e.g., 125.4 -> -125.4)
// across [100.0, 170.0] while leaving already-negative western longitudes unchanged, and reports
// whether coordinates fall within [45.0..85.0] N, [-170.0..-100.0] W.
func NormalizeWesternBCCoordinates(lat, lon float64) (normLat, normLon float64, flipped, inBounds bool) {
	normLat, normLon = lat, lon
	if math.IsNaN(lat) || math.IsNaN(lon) || math.IsInf(lat, 0) || math.IsInf(lon, 0) {
		return lat, lon, false, false
	}
	if normLon >= -WesternBCMaxLon && normLon <= -WesternBCMinLon {
		normLon = -normLon
		flipped = true
	}
	inBounds = normLat >= WesternBCMinLat && normLat <= WesternBCMaxLat && normLon >= WesternBCMinLon && normLon <= WesternBCMaxLon
	return normLat, normLon, flipped, inBounds
}

// NegateLocationLongitude returns the signed Western Hemisphere display longitude for stored numeric coordinates:
// positive stored magnitudes within the Western-BC / Alaska / Canadian North span [100.0, 170.0]
// (Access unsigned-West convention, e.g. 125.4) are negated to -125.4, whereas already-negative longitudes
// (e.g. -125.4, -179.9) and Eastern Hemisphere / out-of-range longitudes (e.g. +179.9, 0, +200) are preserved
// without silent antimeridian flipping or clamping.
func NegateLocationLongitude(cell ProjectMetadataCell) (ProjectMetadataCell, error) {
	if _, err := MetadataCellValue(cell); err != nil {
		return ProjectMetadataCell{}, err
	}
	switch cell.Storage {
	case "integer":
		value, err := strconv.ParseInt(*cell.Integer, 10, 64)
		if err != nil || value == math.MinInt64 {
			return ProjectMetadataCell{}, errors.New("location longitude negation exceeds exact numeric range; original storage unchanged")
		}
		if value >= int64(-WesternBCMaxLon) && value <= int64(-WesternBCMinLon) {
			text := strconv.FormatInt(-value, 10)
			return ProjectMetadataCell{Storage: "integer", Integer: &text}, nil
		}
		text := strconv.FormatInt(value, 10)
		return ProjectMetadataCell{Storage: "integer", Integer: &text}, nil
	case "real":
		value := *cell.Real
		if value >= -WesternBCMaxLon && value <= -WesternBCMinLon {
			negated := -value
			return ProjectMetadataCell{Storage: "real", Real: &negated}, nil
		}
		return ProjectMetadataCell{Storage: "real", Real: &value}, nil
	default:
		return ProjectMetadataCell{}, errors.New("location longitude requires original numeric storage; no text/BLOB coercion or inferred coordinates")
	}
}

func PlanPlotLocations(ctx context.Context, project, suName string, env, admin, su ProjectMetadataTable) (*PlotLocationReport, error) {
	if !ProjectNamePattern.MatchString(project) || !ProjectNamePattern.MatchString(suName) {
		return nil, errors.New("plot location report requires literal desktop project/SU identities")
	}
	fields := PlotLocationFields()
	required := make([]string, len(fields))
	for i, field := range fields {
		required[i] = field.Key
	}
	ec, err := SiteUnitTransferColumns(env, required...)
	if err != nil {
		return nil, fmt.Errorf("plot location Env schema: %w", err)
	}
	ac, err := SiteUnitTransferColumns(admin, "Plot")
	if err != nil {
		return nil, fmt.Errorf("plot location Admin schema: %w", err)
	}
	parents, err := SiteUnitTransferIndex(admin, ac["Plot"])
	if err != nil {
		return nil, err
	}
	envIndex, err := SiteUnitTransferIndex(env, ec["PlotNumber"])
	if err != nil {
		return nil, err
	}
	for _, index := range []map[string][]ProjectMetadataRow{parents, envIndex} {
		for _, rows := range index {
			if len(rows) > 1 {
				return nil, errors.New("plot location report rejects ambiguous physical Env/Admin plot links")
			}
		}
	}
	memberships := map[string][]ProjectMetadataRow{}
	if suName != "None" {
		sc, err := SiteUnitTransferColumns(su, "PlotNumber")
		if err != nil {
			return nil, fmt.Errorf("plot location selected SU schema: %w", err)
		}
		memberships, err = SiteUnitTransferIndex(su, sc["PlotNumber"])
		if err != nil {
			return nil, err
		}
	}
	report := &PlotLocationReport{Project: project, SU: suName, Fields: fields, Rows: []PlotLocationRow{}}
	for _, row := range env.Rows {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		plot := row.Cells[ec["PlotNumber"]].Text
		if plot == nil || len(parents[*plot]) != 1 || suName != "None" && len(memberships[*plot]) == 0 {
			continue
		}
		longitude, latitude := row.Cells[ec["Longitude"]], row.Cells[ec["Latitude"]]
		for _, cell := range []ProjectMetadataCell{longitude, latitude} {
			if _, err := MetadataCellValue(cell); err != nil {
				return nil, err
			}
		}
		if longitude.Storage == "null" || latitude.Storage == "null" {
			continue
		}
		if latitude.Storage != "integer" && latitude.Storage != "real" {
			return nil, errors.New("location latitude requires original numeric storage; no inferred or converted coordinates")
		}
		converted, err := NegateLocationLongitude(longitude)
		if err != nil {
			return nil, err
		}
		entry := PlotLocationRow{EnvRowID: row.RowID, AdminRowID: parents[*plot][0].RowID,
			MembershipRowIDs: []string{}, StoredLongitude: CloneSiteUnitCell(longitude),
			Values: make([]ProjectMetadataCell, len(fields))}
		for i, field := range fields {
			cell := row.Cells[ec[field.Key]]
			if _, err := MetadataCellValue(cell); err != nil {
				return nil, err
			}
			entry.Values[i] = CloneSiteUnitCell(cell)
		}
		entry.Values[6] = converted
		for _, member := range memberships[*plot] {
			entry.MembershipRowIDs = append(entry.MembershipRowIDs, member.RowID)
		}
		report.Rows = append(report.Rows, entry)
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return report, nil
}
