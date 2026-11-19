package interchange

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"math"

	"github.com/boostao/vpro/app/internal/vprocore"
)

// ProjectBCAlbersToNAD83 implements Snyder's iterative inverse GRS80 Albers projection (eqs. 14-19, 3-16).
func ProjectBCAlbersToNAD83(easting, northing float64) (latDeg, lonDeg float64) {
	dx := easting - bcAlbersFalseE
	dy := bcAlbersRho0 - (northing - bcAlbersFalseN)
	rho := math.Hypot(dx, dy)
	if bcAlbersN < 0 {
		rho = -rho
		dx = -dx
		dy = -dy
	}
	theta := 0.0
	if rho != 0 {
		theta = math.Atan2(dx, dy)
	}
	q := (bcAlbersC - (rho*bcAlbersN/grs80SemiMajor)*(rho*bcAlbersN/grs80SemiMajor)) / bcAlbersN
	qMax := (1.0 - grs80E2) * (1.0/(1.0-grs80E2) - (1.0/(2.0*grs80E))*math.Log((1.0-grs80E)/(1.0+grs80E)))
	arg := q / qMax
	if arg > 1 {
		arg = 1
	} else if arg < -1 {
		arg = -1
	}
	phi := math.Asin(arg)
	for iter := 0; iter < 12; iter++ {
		s := math.Sin(phi)
		es := grs80E * s
		oneMinusE2S2 := 1.0 - grs80E2*s*s
		dPhi := (oneMinusE2S2 * oneMinusE2S2 / (2.0 * math.Cos(phi))) *
			(q/(1.0-grs80E2) - s/oneMinusE2S2 + (1.0/(2.0*grs80E))*math.Log((1.0-es)/(1.0+es)))
		phi += dPhi
		if math.Abs(dPhi) < 1e-12 {
			break
		}
	}
	lam := bcAlbersLam0 + theta/bcAlbersN
	return phi * 180.0 / math.Pi, lam * 180.0 / math.Pi
}

// DecodeGeoPackagePoint parses a GeoPackage Binary Point for verification and tests.
func DecodeGeoPackagePoint(blob []byte) (srsID int32, x, y float64, err error) {
	if len(blob) < 29 || blob[0] != 'G' || blob[1] != 'P' {
		return 0, 0, 0, errors.New("invalid GeoPackage binary magic")
	}
	flags := blob[3]
	leHeader := (flags & 0x01) != 0
	envCode := (flags >> 1) & 0x07
	envBytes := 0
	switch envCode {
	case 0:
		envBytes = 0
	case 1:
		envBytes = 32
	case 2, 3:
		envBytes = 48
	case 4:
		envBytes = 64
	default:
		return 0, 0, 0, fmt.Errorf("invalid GeoPackage envelope indicator %d", envCode)
	}
	if leHeader {
		srsID = int32(binary.LittleEndian.Uint32(blob[4:8]))
	} else {
		srsID = int32(binary.BigEndian.Uint32(blob[4:8]))
	}
	wkbStart := 8 + envBytes
	if len(blob) < wkbStart+21 {
		return 0, 0, 0, errors.New("truncated GeoPackage WKB Point")
	}
	wkb := blob[wkbStart:]
	wkbLE := wkb[0] == 1
	var wkbType uint32
	if wkbLE {
		wkbType = binary.LittleEndian.Uint32(wkb[1:5])
		x = math.Float64frombits(binary.LittleEndian.Uint64(wkb[5:13]))
		y = math.Float64frombits(binary.LittleEndian.Uint64(wkb[13:21]))
	} else {
		wkbType = binary.BigEndian.Uint32(wkb[1:5])
		x = math.Float64frombits(binary.BigEndian.Uint64(wkb[5:13]))
		y = math.Float64frombits(binary.BigEndian.Uint64(wkb[13:21]))
	}
	if wkbType != 1 {
		return 0, 0, 0, fmt.Errorf("expected WKB Point (1), got %d", wkbType)
	}
	return srsID, x, y, nil
}

// Private preparation only: no desktop approval, feature gate or export API.
func PublishOwnedProjectTableCSV(s *vprocore.ContextService, ctx context.Context, contextID string, expected ownedTableCSVReview, requested string) (tableCSVPublication, error) {
	return PublishOwnedProjectTableCSVWithHooks(s, ctx, contextID, expected, requested, tableCSVOwnedPublicationHooks{})
}

func PublishOwnedProjectTableCSVWithHooks(s *vprocore.ContextService, ctx context.Context, contextID string, expected ownedTableCSVReview, requested string, hooks tableCSVOwnedPublicationHooks) (tableCSVPublication, error) {
	return PublishOwnedProjectTableCSVUsing(s, ctx, contextID, expected, requested, hooks,
		func(ctx context.Context, requested string, review ownedTableCSVReview, validate func() error, hooks tableCSVPublicationHooks) (tableCSVPublication, error) {
			return publishTableCSVBundleChecked(ctx, requested, review.Document, validate, hooks)
		})
}

func PublishOwnedProjectTableCSVArchive(s *vprocore.ContextService, ctx context.Context, contextID string, expected ownedTableCSVReview, requested string) (tableCSVPublication, error) {
	return PublishOwnedProjectTableCSVArchiveWithHooks(s, ctx, contextID, expected, requested, tableCSVOwnedPublicationHooks{})
}

// This private container publishes neither files nor databases. Its byte budget
// bounds both the whole input archive and the aggregate uncompressed members.
func encodeTableCSVBundle(ctx context.Context, document tableCSVDocument) ([]byte, error) {
	document = snapshotTableCSVBundleDocument(document)
	if _, err := decodeTableCSV(ctx, document); err != nil {
		return nil, fmt.Errorf("table CSV bundle document: %w", err)
	}
	manifest, err := json.Marshal(document.Manifest)
	if err != nil {
		return nil, fmt.Errorf("table CSV bundle manifest: %w", err)
	}
	if err := validateTableCSVBundleManifest(ctx, manifest); err != nil {
		return nil, fmt.Errorf("table CSV bundle manifest: %w", err)
	}
	return encodeTableCSVBundleMembers(ctx, document.Data, manifest)
}

func decodeTableCSVBundle(ctx context.Context, encoded []byte, byteBudget int64) (tableCSVDocument, error) {
	var zero tableCSVDocument
	contents, err := decodeTableCSVBundleMembers(ctx, encoded, byteBudget)
	if err != nil {
		return zero, err
	}
	if err := validateTableCSVBundleManifest(ctx, contents["manifest.json"]); err != nil {
		return zero, fmt.Errorf("table CSV bundle manifest: %w", err)
	}
	var manifest TableCSVManifest
	if err := json.Unmarshal(contents["manifest.json"], &manifest); err != nil {
		return zero, fmt.Errorf("table CSV bundle manifest decode: %w", err)
	}
	document := tableCSVDocument{Manifest: manifest, Data: contents["table.csv"]}
	if _, err := decodeTableCSV(ctx, document); err != nil {
		return zero, fmt.Errorf("table CSV bundle document: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return zero, fmt.Errorf("table CSV bundle decode: %w", err)
	}
	return document, nil
}

// Bounded to the four object shapes in this manifest, not an application-wide
// JSON policy. Inspect every raw string before encoding/json can repair Unicode.
func validateTableCSVBundleManifest(ctx context.Context, raw []byte) error {
	return validateTableCSVBundleJSON(ctx, raw, "manifest")
}

func publishTableCSVBundle(ctx context.Context, requested string, document tableCSVDocument) (tableCSVPublication, error) {
	return publishTableCSVBundleWithHooks(ctx, requested, document, tableCSVPublicationHooks{})
}

func publishTableCSVBundleWithHooks(ctx context.Context, requested string, document tableCSVDocument, hooks tableCSVPublicationHooks) (tableCSVPublication, error) {
	return publishTableCSVBundleChecked(ctx, requested, document, nil, hooks)
}

func publishTableCSVBundleChecked(ctx context.Context, requested string, document tableCSVDocument, validateSource func() error, hooks tableCSVPublicationHooks) (tableCSVPublication, error) {
	document = snapshotTableCSVBundleDocument(document)
	return vprocore.PublishArtifactChecked(ctx, requested, vprocore.ArtifactPublicationFormat{
		Label:        "table CSV publication",
		Artifact:     "bundle",
		CommitLabel:  "table CSV bundle",
		StagePattern: ".vpro-table-csv-*",
		Encode: func(ctx context.Context) ([]byte, error) {
			return encodeTableCSVBundle(ctx, document)
		},
		Validate: func(ctx context.Context, encoded []byte) error {
			_, err := decodeTableCSVBundle(ctx, encoded, int64(len(encoded)))
			return err
		},
	}, validateSource, hooks)
}
