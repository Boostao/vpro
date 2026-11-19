package pictures

import (
	"context"
	"encoding/json"
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/internal/vprocore"
	"github.com/boostao/vpro/app/internal/vprocore/vprotest"
)

func pictureServiceLookup(values map[string]string) func(string) (string, bool) {
	return func(name string) (string, bool) {
		value, present := values[name]
		return value, present
	}
}

func TestPictureServiceExplicitSourcesAndGuards(t *testing.T) {
	if service, err := NewPictureService(&vprocore.ContextService{}, pictureServiceLookup(nil)); service != nil || err == nil {
		t.Fatal("missing library and project root silently defaulted", service, err)
	}
	if service, err := NewPictureService(&vprocore.ContextService{}, pictureServiceLookup(map[string]string{pictureLibraryEnvironment: ""})); service != nil || err == nil {
		t.Fatal("empty explicit library path accepted", service, err)
	}
	if service, err := NewPictureService(nil, pictureServiceLookup(nil)); service != nil || err == nil {
		t.Fatal("nil context owner constructed a picture service", service, err)
	}
	if service, err := NewPictureService(&vprocore.ContextService{}, nil); service != nil || err == nil {
		t.Fatal("missing explicit lookup constructed a picture service", service, err)
	}
	var missing *PictureService
	if got, err := missing.GetMetadata(context.Background(), "owned", "P"); err == nil || got != nil {
		t.Fatal("nil service produced metadata", got, err)
	}
	//lint:ignore SA1012 intentional nil-context guard test
	if err := missing.require(nil); err == nil {
		t.Fatal("nil request context was accepted")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := missing.require(ctx); !errors.Is(err, context.Canceled) {
		t.Fatal("cancelled request produced success-shaped availability", err)
	}
}

func TestPictureServiceStrictReviewedPreviewAndReadOnlyMethods(t *testing.T) {
	contexts, state := vprotest.ReportServiceFixture(t, false)
	source, path := pictureLibraryFixture(t, pictureFixtureSchema)
	directory, _ := pictureImageFixture(t, "jpeg", 448, 300)
	values := map[string]string{
		pictureLibraryEnvironment:        path,
		pictureChildDirectoryEnvironment: directory.path,
	}
	service, err := NewPictureService(contexts, pictureServiceLookup(values))
	if err != nil {
		t.Fatal(err)
	}
	metadata, err := service.GetMetadata(context.Background(), state.ContextID, "108050")
	expected, expectedErr := ReadPictureMetadata(contexts, context.Background(), state.ContextID, "108050", source)
	if err != nil || expectedErr != nil || metadata == nil || !reflect.DeepEqual(*metadata, expected) {
		t.Fatal("facade changed complete physical metadata", metadata, err, expectedErr)
	}
	request := PictureImageRequest{View: pictureChildView, Original: metadata.Records.Rows[3]}
	data, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	valid := string(data)
	for _, malformed := range []string{
		`{}`, `{"view":"child","original":null}`, `{"view":null,"original":{}}`,
		strings.Replace(valid, `"view":`, `"unknown":true,"view":`, 1),
		strings.Replace(valid, `"view":"child"`, `"view":"manager","view":"child"`, 1),
		strings.Replace(valid, `"view":"child"`, `"view":"Child"`, 1),
		strings.Replace(valid, `"original":`, `"Original":`, 1),
		strings.Replace(valid, `"rowId":`, `"rowId":"1","rowId":`, 1),
		strings.Replace(valid, `"rowId":`, `"rowId":"\ud800","ignored":`, 1),
		strings.Replace(valid, `"cells":`, `"cells":null,"cells":`, 1),
		strings.Replace(valid, `"storage":`, `"storage":"null","storage":`, 1),
		strings.Replace(valid, `"storage":`, `"Storage":`, 1),
		strings.Replace(valid, `"blobHex":`, `"unknown":null,"blobHex":`, 1),
		strings.Replace(valid, `"text":"Default"`, `"text":"\ud800"`, 1),
		strings.Replace(valid, `"text":"Default"`, "\"text\":\""+string([]byte{0xff})+"\"", 1),
		valid + `{}`,
	} {
		if got, err := service.GetImage(context.Background(), state.ContextID, "108050", malformed); err == nil || got != nil {
			t.Fatal("malformed/duplicate/raw Unicode authority returned a preview", malformed, got, err)
		}
	}
	for _, test := range []struct{ contextID, plot string }{
		{"stale", "108050"}, {state.ContextID, "missing"}, {state.ContextID, "108050 "},
	} {
		if got, err := service.GetImage(context.Background(), test.contextID, test.plot, valid); err == nil || got != nil {
			t.Fatal("foreign context/plot preview succeeded", got, err)
		}
	}
	got, err := service.GetImage(context.Background(), state.ContextID, "108050", valid)
	if err != nil || got == nil || got.Width != 448 || got.Height != 300 || got.RowID != request.Original.RowID {
		t.Fatal("facade did not preserve owned measured image", got, err)
	}
	request.View = pictureManagerView
	data, err = json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := service.GetImage(context.Background(), state.ContextID, "108050", string(data)); err == nil || got != nil {
		t.Fatal("manager preview implicitly inherited child directory permission", got, err)
	}
	if _, err := service.SaveMetadata(context.Background(), state.ContextID, "108050", "{}"); err == nil {
		t.Fatal("read-only PictureService without attached metadata writer accepted SaveMetadata")
	}
	if _, err := service.CreatePicture(context.Background(), "token", "{}"); err == nil {
		t.Fatal("read-only PictureService without attached creation writer accepted CreatePicture")
	}
	if _, err := service.DeletePicture(context.Background(), state.ContextID, "{}"); err == nil {
		t.Fatal("read-only PictureService without attached deletion writer accepted DeletePicture")
	}
	kind := reflect.TypeOf(service)
	if kind.NumMethod() != 19 {
		t.Fatal("consolidated PictureService domain method count changed", kind.NumMethod())
	}
}

func TestPictureServiceOptionsLifecyclePersistenceAndValidation(t *testing.T) {
	contexts, state := vprotest.ContextServiceFixture(t)
	defaultLib, defaultImgs, err := vprocore.EnsureDefaultPictureLibrary(contexts.Projects.Root)
	if err != nil {
		t.Fatalf("EnsureDefaultPictureLibrary: %v", err)
	}
	emptyLookup := pictureServiceLookup(nil)

	service, err := NewPictureServiceWithDefaults(contexts, emptyLookup, defaultLib, defaultImgs)
	if err != nil {
		t.Fatalf("NewPictureServiceWithDefaults: %v", err)
	}
	creation, err := NewPictureCreationService(service)
	if err != nil {
		t.Fatalf("NewPictureCreationService: %v", err)
	}
	service.Creation = creation

	initial, err := service.GetPictureOptions(context.Background())
	if err != nil {
		t.Fatalf("GetPictureOptions: %v", err)
	}
	if initial.PictureLibraryPath != "" || initial.ChildDirectory != "" || initial.ManagerDirectory != "" ||
		initial.EffectiveLibraryPath != defaultLib || initial.EffectiveChildDirectory != defaultImgs ||
		initial.EffectiveManagerDirectory != defaultImgs || initial.EnvOverride {
		t.Fatalf("unexpected initial PictureOptions: %+v", initial)
	}

	// Custom valid VPics library + custom child/manager image directories
	_, customLibPath := pictureLibraryFixture(t, pictureFixtureSchema)
	customChildDir, _ := pictureImageFixture(t, "jpeg", 120, 90)
	customManagerDir, _ := pictureImageFixture(t, "png", 160, 120)

	saved, err := service.SavePictureOptions(context.Background(), PictureOptionsUpdate{
		PictureLibraryPath: "  " + customLibPath + "  ",
		ChildDirectory:     "  " + customChildDir.path + "  ",
		ManagerDirectory:   "  " + customManagerDir.path + "  ",
	})
	if err != nil {
		t.Fatalf("SavePictureOptions custom paths failed: %v", err)
	}
	if saved.PictureLibraryPath != customLibPath ||
		saved.ChildDirectory != customChildDir.path ||
		saved.ManagerDirectory != customManagerDir.path ||
		saved.EffectiveLibraryPath != customLibPath ||
		saved.EffectiveChildDirectory != customChildDir.path ||
		saved.EffectiveManagerDirectory != customManagerDir.path {
		t.Fatalf("SavePictureOptions did not apply custom paths live: %+v", saved)
	}

	// Verify reopened service from config.yml honors persisted PictureOptions over defaults
	reopened, err := NewPictureServiceWithDefaults(contexts, emptyLookup, defaultLib, defaultImgs)
	if err != nil {
		t.Fatalf("reopen NewPictureServiceWithDefaults failed: %v", err)
	}
	reopenedOpts, err := reopened.GetPictureOptions(context.Background())
	if err != nil {
		t.Fatalf("reopened GetPictureOptions failed: %v", err)
	}
	if reopenedOpts.EffectiveLibraryPath != customLibPath ||
		reopenedOpts.EffectiveChildDirectory != customChildDir.path ||
		reopenedOpts.EffectiveManagerDirectory != customManagerDir.path {
		t.Fatalf("persisted PictureOptions not honored on reopen: %+v", reopenedOpts)
	}

	// Reject invalid paths, non-VPics SQLite files, and aliased context DBs without mutating live options
	_, nonVPicsPath := pictureLibraryFixture(t, `CREATE TABLE NotVPics(ID INTEGER);`)
	for _, bad := range []PictureOptionsUpdate{
		{PictureLibraryPath: "relative/VPics.db"},
		{PictureLibraryPath: customLibPath + "\x00"},
		{PictureLibraryPath: nonVPicsPath},
		{PictureLibraryPath: contexts.Projects.Sqlite.Selection.ProjectPath},
		{ChildDirectory: "relative/images"},
		{ManagerDirectory: customLibPath}, // regular file, not directory
	} {
		if _, err := service.SavePictureOptions(context.Background(), bad); err == nil {
			t.Fatalf("expected invalid PictureOptionsUpdate %+v to fail", bad)
		}
	}

	// Reject reconfiguration while an active picture selection token is open
	service.Creation.mu.Lock()
	service.Creation.tokens["active-token"] = &pictureCreationCapability{
		dto: PictureCreationSelection{Token: "active-token", ContextID: state.ContextID, Project: state.ActiveProject, PlotNumber: "00337"},
	}
	service.Creation.mu.Unlock()
	if _, err := service.SavePictureOptions(context.Background(), PictureOptionsUpdate{}); err == nil || !strings.Contains(err.Error(), "active picture") {
		t.Fatalf("expected active selection token to block SavePictureOptions, got %v", err)
	}
	service.Creation.mu.Lock()
	delete(service.Creation.tokens, "active-token")
	service.Creation.mu.Unlock()

	// Reset back to workspace defaults ("")
	reset, err := service.SavePictureOptions(context.Background(), PictureOptionsUpdate{})
	if err != nil {
		t.Fatalf("SavePictureOptions reset to defaults failed: %v", err)
	}
	if reset.PictureLibraryPath != "" || reset.ChildDirectory != "" || reset.ManagerDirectory != "" ||
		reset.EffectiveLibraryPath != defaultLib || reset.EffectiveChildDirectory != defaultImgs ||
		reset.EffectiveManagerDirectory != defaultImgs {
		t.Fatalf("reset PictureOptions did not restore workspace defaults: %+v", reset)
	}
}

func TestPictureServiceOptionalDirectoryConfigurationIsNotRepaired(t *testing.T) {
	contexts, state := vprotest.ReportServiceFixture(t, false)
	_, path := pictureLibraryFixture(t, pictureFixtureSchema)
	values := map[string]string{pictureLibraryEnvironment: path}
	service, err := NewPictureService(contexts, pictureServiceLookup(values))
	if err != nil {
		t.Fatal("explicit metadata-only library required an inferred image directory", err)
	}
	if _, err := service.GetMetadata(context.Background(), state.ContextID, "108050"); err != nil {
		t.Fatal("metadata-only optional library was unavailable", err)
	}
	for _, name := range []string{pictureChildDirectoryEnvironment, pictureManagerDirectoryEnvironment} {
		for _, path := range []string{"", "relative", "invalid\x00", string([]byte{0xff})} {
			values[name] = path
			if got, err := NewPictureService(contexts, pictureServiceLookup(values)); err == nil || got != nil {
				t.Fatal("configured invalid/empty directory was silently defaulted or repaired", name, path, got, err)
			}
		}
		delete(values, name)
	}
}
