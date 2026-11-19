package spatial

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"html"
	"math"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/vprocore"
)

const googleEarthKMLNamespace = "http://earth.google.com/kml/2.1"

// These are explicitly prepared text and map coordinates, not raw database
// cells. Longitude is already east-positive; this boundary never negates it.
type googleEarthKMLPoint struct {
	Name, Description   string
	Longitude, Latitude float64
}

type googleEarthKMLPlacemark struct {
	Name        string `xml:"name"`
	Description string `xml:"description"`
	Point       struct {
		Coordinates string `xml:"coordinates"`
	} `xml:"Point"`
}

func validateGoogleEarthXMLText(value string) error {
	if !utf8.ValidString(value) {
		return fmt.Errorf("invalid UTF-8; XML text is not repaired")
	}
	for _, char := range value {
		if char != '\t' && char != '\n' && char != '\r' &&
			!(char >= 0x20 && char <= 0xd7ff || char >= 0xe000 && char <= 0xfffd || char >= 0x10000 && char <= 0x10ffff) {
			return fmt.Errorf("character U+%04X is not XML 1.0 text", char)
		}
	}
	return nil
}

func validateGoogleEarthKMLCoordinates(longitude, latitude float64) error {
	if math.IsNaN(longitude) || math.IsInf(longitude, 0) || longitude < -180 || longitude > 180 ||
		math.IsNaN(latitude) || math.IsInf(latitude, 0) || latitude < -90 || latitude > 90 {
		return fmt.Errorf("requires finite longitude [-180,180] and latitude [-90,90]; values are not clamped")
	}
	return nil
}

func prepareGoogleEarthKML(ctx context.Context, title string, points []googleEarthKMLPoint) ([]byte, error) {
	points = append([]googleEarthKMLPoint(nil), points...)
	if ctx == nil {
		return nil, fmt.Errorf("Google Earth KML preparation requires a context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if err := validateGoogleEarthXMLText(title); err != nil {
		return nil, fmt.Errorf("Google Earth document name: %w", err)
	}
	for i, point := range points {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		plotLabel := fmt.Sprintf("plot %q", point.Name)
		if strings.TrimSpace(point.Name) == "" {
			plotLabel = fmt.Sprintf("unnamed plot (#%d)", i+1)
		}
		for _, field := range []struct{ name, value string }{{"name", point.Name}, {"description", point.Description}} {
			if err := validateGoogleEarthXMLText(field.value); err != nil {
				return nil, fmt.Errorf("Google Earth KML %s %s: %w", plotLabel, field.name, err)
			}
		}
		if err := validateGoogleEarthKMLCoordinates(point.Longitude, point.Latitude); err != nil {
			return nil, fmt.Errorf("Google Earth KML %s coordinates (latitude %s, longitude %s): %w",
				plotLabel,
				strconv.FormatFloat(point.Latitude, 'f', -1, 64),
				strconv.FormatFloat(point.Longitude, 'f', -1, 64),
				err)
		}
	}
	var buffer bytes.Buffer
	buffer.WriteString(xml.Header)
	encoder := xml.NewEncoder(&buffer)
	root := xml.StartElement{Name: xml.Name{Space: googleEarthKMLNamespace, Local: "kml"}}
	document := xml.StartElement{Name: xml.Name{Local: "Document"}}
	if err := encoder.EncodeToken(root); err != nil {
		return nil, fmt.Errorf("encode Google Earth root: %w", err)
	}
	if err := encoder.EncodeToken(document); err != nil {
		return nil, fmt.Errorf("encode Google Earth document: %w", err)
	}
	if err := encoder.EncodeElement(title, xml.StartElement{Name: xml.Name{Local: "name"}}); err != nil {
		return nil, fmt.Errorf("encode Google Earth document name: %w", err)
	}
	for i, point := range points {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		mark := googleEarthKMLPlacemark{Name: point.Name, Description: html.EscapeString(point.Description + ".")}
		mark.Point.Coordinates = strconv.FormatFloat(point.Longitude, 'f', -1, 64) + "," +
			strconv.FormatFloat(point.Latitude, 'f', -1, 64) + ",0"
		if err := encoder.EncodeElement(mark, xml.StartElement{Name: xml.Name{Local: "Placemark"}}); err != nil {
			return nil, fmt.Errorf("encode Google Earth point %d: %w", i, err)
		}
	}
	if err := encoder.EncodeToken(document.End()); err != nil {
		return nil, fmt.Errorf("finish Google Earth document: %w", err)
	}
	if err := encoder.EncodeToken(root.End()); err != nil {
		return nil, fmt.Errorf("finish Google Earth root: %w", err)
	}
	if err := encoder.Flush(); err != nil {
		return nil, fmt.Errorf("flush Google Earth XML: %w", err)
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return append([]byte(nil), buffer.Bytes()...), nil
}

func googleEarthKMLText(cell vprocore.ProjectMetadataCell) (string, error) {
	value, err := vprocore.MetadataCellValue(cell)
	if err != nil {
		return "", err
	}
	switch cell.Storage {
	case "null":
		return "", nil
	case "text":
		text := value.(string)
		if err := validateGoogleEarthXMLText(text); err != nil {
			return "", err
		}
		return text, nil
	default:
		return "", fmt.Errorf("KML text formatting for storage %q is unavailable; no implicit conversion", cell.Storage)
	}
}

func googleEarthKMLNumber(cell vprocore.ProjectMetadataCell) (float64, error) {
	value, err := vprocore.MetadataCellValue(cell)
	if err != nil {
		return 0, err
	}
	switch number := value.(type) {
	case int64:
		return float64(number), nil
	case float64:
		return number, nil
	default:
		return 0, fmt.Errorf("KML coordinates require original numeric storage, not %q", cell.Storage)
	}
}

// Rows come from the private direct-Env projection; this does not authorize a
// database read. Longitude is its already-negated value, not StoredLongitude.
func planGoogleEarthKMLPoints(ctx context.Context, rows []googleEarthLocation) ([]googleEarthKMLPoint, error) {
	rows = append([]googleEarthLocation(nil), rows...)
	for i := range rows {
		rows[i].PlotNumber = vprocore.CloneSiteUnitCell(rows[i].PlotNumber)
		rows[i].Longitude = vprocore.CloneSiteUnitCell(rows[i].Longitude)
		rows[i].Latitude = vprocore.CloneSiteUnitCell(rows[i].Latitude)
		rows[i].Description = vprocore.CloneSiteUnitCell(rows[i].Description)
	}
	if ctx == nil {
		return nil, fmt.Errorf("Google Earth KML points require a context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	points := make([]googleEarthKMLPoint, 0, len(rows))
	var badCoordSummaries []string
	var firstCoordErr error
	for i, row := range rows {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		name, err := googleEarthKMLText(row.PlotNumber)
		if err != nil {
			return nil, fmt.Errorf("Google Earth KML plot number (#%d) PlotNumber: %w", i+1, err)
		}
		plotLabel := fmt.Sprintf("plot %q", name)
		if strings.TrimSpace(name) == "" {
			plotLabel = fmt.Sprintf("unnamed plot (#%d)", i+1)
		}
		description, err := googleEarthKMLText(row.Description)
		if err != nil {
			return nil, fmt.Errorf("Google Earth KML %s description: %w", plotLabel, err)
		}
		longitude, err := googleEarthKMLNumber(row.Longitude)
		if err != nil {
			return nil, fmt.Errorf("Google Earth KML %s Longitude: %w", plotLabel, err)
		}
		latitude, err := googleEarthKMLNumber(row.Latitude)
		if err != nil {
			return nil, fmt.Errorf("Google Earth KML %s Latitude: %w", plotLabel, err)
		}
		if err := validateGoogleEarthKMLCoordinates(longitude, latitude); err != nil {
			if firstCoordErr == nil {
				firstCoordErr = err
			}
			badCoordSummaries = append(badCoordSummaries, fmt.Sprintf(
				"%s (latitude %s, longitude %s)",
				plotLabel,
				strconv.FormatFloat(latitude, 'f', -1, 64),
				strconv.FormatFloat(longitude, 'f', -1, 64),
			))
			continue
		}
		points = append(points, googleEarthKMLPoint{Name: name, Description: description, Longitude: longitude, Latitude: latitude})
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if len(badCoordSummaries) > 0 {
		shown := badCoordSummaries
		suffix := ""
		if len(shown) > 5 {
			suffix = fmt.Sprintf(" (and %d more)", len(shown)-5)
			shown = shown[:5]
		}
		if len(badCoordSummaries) == 1 {
			return nil, fmt.Errorf("Google Earth KML cannot export %s because its coordinates are out of range (%w)", shown[0], firstCoordErr)
		}
		return nil, fmt.Errorf("Google Earth KML cannot export %d plots with out-of-range coordinates [%s]%s (%w)",
			len(badCoordSummaries), strings.Join(shown, "; "), suffix, firstCoordErr)
	}
	return points, nil
}

type ownedGoogleEarthKML struct {
	ContextID, ProjectPath, SUPath string
	Project, SU, DescriptionField  string
	Title                          string
	PlacemarkCount                 int
	Bytes                          []byte
}

type ownedGoogleEarthKMLPreparation struct {
	Source ownedGoogleEarthLocations
	KML    ownedGoogleEarthKML
}

func readGoogleEarthKMLPreparationSnapshot(ctx context.Context, contextID, descriptionField, title string, owner *vprocore.SqliteContext, tx *sql.Tx) (*ownedGoogleEarthKMLPreparation, error) {
	source, err := readGoogleEarthLocationsSnapshot(ctx, contextID, descriptionField, owner, tx)
	if err != nil {
		return nil, err
	}
	points, err := planGoogleEarthKMLPoints(ctx, source.Report.Rows)
	if err != nil {
		return nil, err
	}
	data, err := prepareGoogleEarthKML(ctx, title, points)
	if err != nil {
		return nil, err
	}
	return &ownedGoogleEarthKMLPreparation{Source: *source, KML: ownedGoogleEarthKML{
		ContextID: source.ContextID, ProjectPath: source.ProjectPath,
		SUPath: source.SUPath, Project: source.Report.Project, SU: source.Report.SU,
		DescriptionField: source.Report.DescriptionField, Title: title,
		PlacemarkCount: len(points), Bytes: data,
	}}, nil
}

func ReadGoogleEarthKML(s *vprocore.ContextService, ctx context.Context, contextID, descriptionField, title string) (*ownedGoogleEarthKML, error) {
	if err := validateGoogleEarthXMLText(title); err != nil {
		return nil, fmt.Errorf("Google Earth document name: %w", err)
	}
	return vprocore.WithContextPlotRequest(ctx, s, contextID, func(plots *vprocore.PlotService) (*ownedGoogleEarthKML, error) {
		return vprocore.WithOwnedSIVISnapshot(ctx, plots, func(owner *vprocore.SqliteContext, tx *sql.Tx) (*ownedGoogleEarthKML, error) {
			preparation, err := readGoogleEarthKMLPreparationSnapshot(ctx, contextID, descriptionField, title, owner, tx)
			if err != nil {
				return nil, err
			}
			return &preparation.KML, nil
		})
	})
}

type GoogleEarthKMLService struct {
	contexts *vprocore.ContextService
}

func NewGoogleEarthKMLService(contexts *vprocore.ContextService) *GoogleEarthKMLService {
	return &GoogleEarthKMLService{contexts: contexts}
}

type GoogleEarthKMLRequest struct {
	DescriptionField string `json:"descriptionField"`
	Title            string `json:"title"`
}

func (request *GoogleEarthKMLRequest) UnmarshalJSON(data []byte) error {
	type plain GoogleEarthKMLRequest
	var decoded plain
	if err := vprocore.DecodeGoogleEarthKMLJSON(data, &decoded, "Google Earth KML preview", "descriptionField", "title"); err != nil {
		return err
	}
	*request = GoogleEarthKMLRequest(decoded)
	return nil
}

type GoogleEarthKMLReview struct {
	ContextID        string `json:"contextId"`
	Project          string `json:"project"`
	ProjectPath      string `json:"projectPath"`
	SU               string `json:"su"`
	SUPath           string `json:"suPath"`
	DescriptionField string `json:"descriptionField"`
	Title            string `json:"title"`
	PlacemarkCount   int    `json:"placemarkCount"`
	ByteCount        int    `json:"byteCount"`
	KML              string `json:"kml"`
}

func (s *GoogleEarthKMLService) GetGoogleEarthKMLReview(ctx context.Context, contextID, requestJSON string) (*GoogleEarthKMLReview, error) {
	if ctx == nil {
		return nil, errors.New("Google Earth KML preview requires a context")
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if s == nil || s.contexts == nil {
		return nil, errors.New("Google Earth KML context service is unavailable")
	}
	var request GoogleEarthKMLRequest
	if err := json.Unmarshal([]byte(requestJSON), &request); err != nil {
		return nil, err
	}
	if err := vprocore.ValidateGoogleEarthReviewStrings(contextID, request.DescriptionField, request.Title); err != nil {
		return nil, err
	}
	if request.DescriptionField == "" || strings.ContainsRune(request.DescriptionField, 0) {
		return nil, errors.New("Google Earth KML preview requires a literal physical description field")
	}
	source, err := ReadGoogleEarthKML(s.contexts, ctx, contextID, request.DescriptionField, request.Title)
	if err != nil {
		return nil, err
	}
	review, err := googleEarthKMLReviewFromOwned(source)
	if err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	return review, nil
}

func googleEarthKMLReviewFromOwned(source *ownedGoogleEarthKML) (*GoogleEarthKMLReview, error) {
	if err := vprocore.ValidateGoogleEarthReviewStrings(source.ContextID, source.Project, source.ProjectPath, source.SU,
		source.SUPath, source.DescriptionField, source.Title, string(source.Bytes)); err != nil {
		return nil, err
	}
	return &GoogleEarthKMLReview{ContextID: source.ContextID, Project: source.Project, ProjectPath: source.ProjectPath,
		SU: source.SU, SUPath: source.SUPath, DescriptionField: source.DescriptionField, Title: source.Title,
		PlacemarkCount: source.PlacemarkCount, ByteCount: len(source.Bytes), KML: string(source.Bytes)}, nil
}
