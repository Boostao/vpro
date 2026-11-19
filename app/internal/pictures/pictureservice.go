package pictures

import (
	"github.com/boostao/vpro/app/internal/sourceform"
	"github.com/boostao/vpro/app/internal/sqlutil"
	"github.com/boostao/vpro/app/internal/vprocore"
)

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
)

const (
	pictureLibraryEnvironment          = "VPRO_PICTURE_LIBRARY_PATH"
	pictureChildDirectoryEnvironment   = "VPRO_PICTURE_CHILD_DIRECTORY"
	pictureManagerDirectoryEnvironment = "VPRO_PICTURE_MANAGER_DIRECTORY"
)

type PictureMetadataReview = pictureMetadataReview
type PictureImage = pictureImage

type PictureImageRequest struct {
	View     string                      `json:"view"`
	Original vprocore.ProjectMetadataRow `json:"original"`
}

func (request *PictureImageRequest) UnmarshalJSON(data []byte) error {
	const operation = "picture preview"
	properties, err := sourceform.SourceChildJSONObject(data, operation, []string{"view", "original"}, nil)
	if err != nil {
		return err
	}
	if err := sourceform.SourceChildJSONNonNull(properties, operation, "view", "original"); err != nil {
		return err
	}
	if err := sourceform.SourceChildRowJSON(properties["original"], operation); err != nil {
		return err
	}
	type plain PictureImageRequest
	var decoded plain
	if err := vprocore.DecodeStrictRequiredJSON(data, &decoded, operation, "view", "original"); err != nil {
		return err
	}
	if decoded.View != pictureChildView && decoded.View != pictureManagerView {
		return errors.New("picture preview requires a literal child or manager policy")
	}
	if decoded.Original.RowID == "" || len(decoded.Original.Cells) != 5 {
		return errors.New("picture preview requires one complete reviewed five-column physical row")
	}
	*request = PictureImageRequest(decoded)
	return nil
}

type PictureOptions struct {
	PictureLibraryPath        string `json:"pictureLibraryPath"`
	ChildDirectory            string `json:"childDirectory"`
	ManagerDirectory          string `json:"managerDirectory"`
	EffectiveLibraryPath      string `json:"effectiveLibraryPath"`
	EffectiveChildDirectory   string `json:"effectiveChildDirectory"`
	EffectiveManagerDirectory string `json:"effectiveManagerDirectory"`
	DefaultLibraryPath        string `json:"defaultLibraryPath"`
	DefaultImagesDirectory    string `json:"defaultImagesDirectory"`
	EnvOverride               bool   `json:"envOverride"`
}

type PictureOptionsUpdate struct {
	PictureLibraryPath string `json:"pictureLibraryPath"`
	ChildDirectory     string `json:"childDirectory"`
	ManagerDirectory   string `json:"managerDirectory"`
}

func (u *PictureOptionsUpdate) UnmarshalJSON(data []byte) error {
	type plain PictureOptionsUpdate
	return sqlutil.DecodeStrictJSON(data, (*plain)(u))
}

type PictureService struct {
	Contexts           *vprocore.ContextService `json:"-" yaml:"-"`
	mu                 sync.RWMutex             `json:"-" yaml:"-"`
	lookup             func(string) (string, bool)
	defaultLibraryPath string
	defaultImagesDir   string
	source             *ownedPictureLibrary
	directories        pictureImageDirectories
	Metadata           *PictureMetadataService `json:"-" yaml:"-"`
	Creation           *PictureCreationService `json:"-" yaml:"-"`
	Deletion           *PictureDeletionService `json:"-" yaml:"-"`
}

func (s *PictureService) currentSource() *ownedPictureLibrary {
	if s == nil {
		return nil
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.source
}

func (s *PictureService) currentDirectories() pictureImageDirectories {
	if s == nil {
		return pictureImageDirectories{}
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.directories
}

func configuredPictureOptions(contexts *vprocore.ContextService) (libraryPath, childDir, managerDir string) {
	if contexts == nil || contexts.Projects == nil || contexts.Projects.Preferences == nil {
		return "", "", ""
	}
	values, err := contexts.Projects.Preferences.Snapshot()
	if err != nil {
		return "", "", ""
	}
	section, err := vprocore.ConfigSection(values, "PictureOptions")
	if err != nil {
		return "", "", ""
	}
	if raw, ok := section["PictureLibraryPath"].(string); ok {
		libraryPath = strings.TrimSpace(raw)
	}
	if raw, ok := section["ChildDirectory"].(string); ok {
		childDir = strings.TrimSpace(raw)
	}
	if raw, ok := section["ManagerDirectory"].(string); ok {
		managerDir = strings.TrimSpace(raw)
	}
	return libraryPath, childDir, managerDir
}

func NewPictureService(contexts *vprocore.ContextService, lookup func(string) (string, bool)) (*PictureService, error) {
	return NewPictureServiceWithDefaults(contexts, lookup, "", "")
}

func NewPictureServiceWithDefaults(contexts *vprocore.ContextService, lookup func(string) (string, bool), defaultLibraryPath, defaultImagesDir string) (*PictureService, error) {
	if contexts == nil || lookup == nil {
		return nil, errors.New("picture service requires context ownership and an explicit environment lookup")
	}
	service := &PictureService{
		Contexts:           contexts,
		lookup:             lookup,
		defaultLibraryPath: strings.TrimSpace(defaultLibraryPath),
		defaultImagesDir:   strings.TrimSpace(defaultImagesDir),
	}
	cfgLibPath, cfgChildDir, cfgManagerDir := configuredPictureOptions(contexts)
	source, dirs, err := service.resolveSources(cfgLibPath, cfgChildDir, cfgManagerDir)
	if err != nil {
		return nil, err
	}
	service.source = source
	service.directories = dirs
	return service, nil
}

func (s *PictureService) fallbackDefaults() (defaultLibPath, defaultPicDir string, err error) {
	defaultLibPath = s.defaultLibraryPath
	defaultPicDir = s.defaultImagesDir
	hasRoot := s.Contexts != nil && s.Contexts.Projects != nil && strings.TrimSpace(s.Contexts.Projects.Root) != ""
	if defaultLibPath == "" && hasRoot {
		defaultLibPath, err = vprocore.InstallVPicsDatabase(s.Contexts.Projects.Root)
		if err != nil {
			return "", "", fmt.Errorf("install canonical VPics.db: %w", err)
		}
	}
	if defaultPicDir == "" && hasRoot {
		defaultPicDir, err = vprocore.EnsurePictureDirectory(s.Contexts.Projects.Root)
		if err != nil {
			return "", "", fmt.Errorf("ensure default picture directory: %w", err)
		}
	}
	return defaultLibPath, defaultPicDir, nil
}

func (s *PictureService) resolveSources(cfgLibPath, cfgChildDir, cfgManagerDir string) (*ownedPictureLibrary, pictureImageDirectories, error) {
	var dirs pictureImageDirectories
	lookup := s.lookup
	if lookup == nil {
		lookup = func(string) (string, bool) { return "", false }
	}
	path, libExplicit := lookup(pictureLibraryEnvironment)
	var defaultPicDir string
	if !libExplicit {
		defaultLibPath, resolvedPicDir, err := s.fallbackDefaults()
		if err != nil {
			return nil, dirs, err
		}
		defaultPicDir = resolvedPicDir
		if cfgLibPath != "" {
			path = cfgLibPath
		} else if defaultLibPath != "" {
			path = defaultLibPath
		} else {
			return nil, dirs, errors.New("picture reading requires VPRO_PICTURE_LIBRARY_PATH; no installed library was inferred")
		}
	} else if path == "" {
		return nil, dirs, errors.New("picture reading requires VPRO_PICTURE_LIBRARY_PATH; no installed library was inferred")
	}
	source, err := newOwnedPictureLibrary(path)
	if err != nil {
		return nil, dirs, err
	}
	for _, entry := range []struct {
		name       string
		cfgPath    string
		defaultDir string
		target     **ownedPictureDirectory
	}{
		{pictureChildDirectoryEnvironment, cfgChildDir, defaultPicDir, &dirs.child},
		{pictureManagerDirectoryEnvironment, cfgManagerDir, defaultPicDir, &dirs.manager},
	} {
		dirPath, present := lookup(entry.name)
		if !present {
			if !libExplicit {
				if entry.cfgPath != "" {
					dirPath = entry.cfgPath
				} else if entry.defaultDir != "" {
					dirPath = entry.defaultDir
				}
			}
			if dirPath == "" {
				continue
			}
		} else if dirPath == "" {
			return nil, dirs, fmt.Errorf("%s must be an explicit directory when configured", entry.name)
		}
		directory, err := newOwnedPictureDirectory(dirPath)
		if err != nil {
			return nil, dirs, fmt.Errorf("%s: %w", entry.name, err)
		}
		*entry.target = directory
	}
	return source, dirs, nil
}

func (s *PictureService) hasEnvOverride() bool {
	if s == nil || s.lookup == nil {
		return false
	}
	for _, key := range []string{pictureLibraryEnvironment, pictureChildDirectoryEnvironment, pictureManagerDirectoryEnvironment} {
		if _, ok := s.lookup(key); ok {
			return true
		}
	}
	return false
}

func (s *PictureService) checkLibraryNotAliased(source *ownedPictureLibrary) error {
	if s == nil || s.Contexts == nil || s.Contexts.Projects == nil || source == nil {
		return nil
	}
	candidates := map[string]string{}
	for role, path := range s.Contexts.Projects.SupportPaths {
		candidates["support:"+role] = path
	}
	if owner := s.Contexts.Projects.Sqlite; owner != nil {
		owner.Mu.Lock()
		for role, path := range owner.Attachments {
			candidates["attachment:"+role] = path
		}
		candidates["selection:project"] = owner.Selection.ProjectPath
		candidates["selection:siteUnit"] = owner.Selection.SUPath
		candidates["selection:hierarchy"] = owner.Selection.HierarchyPath
		if owner.Profile != nil {
			candidates["profile"] = owner.Profile.Path
		}
		owner.Mu.Unlock()
	}
	for role, path := range candidates {
		if strings.TrimSpace(path) == "" {
			continue
		}
		if info, err := os.Stat(path); err == nil && os.SameFile(info, source.info) {
			return fmt.Errorf("picture library path aliases active %s database; select a dedicated VPics.db library file", role)
		}
	}
	return nil
}

func (s *PictureService) checkIdleForReconfigure() error {
	if s.Creation != nil {
		s.Creation.mu.Lock()
		busy := len(s.Creation.tokens) > 0 || len(s.Creation.creating) > 0
		s.Creation.mu.Unlock()
		if busy {
			return errors.New("finish or release active picture attachment selections before changing picture library paths")
		}
	}
	if s.Deletion != nil {
		s.Deletion.mu.Lock()
		busy := len(s.Deletion.mutations) > 0
		s.Deletion.mu.Unlock()
		if busy {
			return errors.New("wait for active picture deletion or restoration operations before changing picture library paths")
		}
	}
	return nil
}

func (s *PictureService) buildOptionsSnapshot() (*PictureOptions, error) {
	cfgLib, cfgChild, cfgManager := configuredPictureOptions(s.Contexts)
	defaultLib, defaultDir, _ := s.fallbackDefaults()
	src := s.currentSource()
	dirs := s.currentDirectories()
	out := &PictureOptions{
		PictureLibraryPath:     cfgLib,
		ChildDirectory:         cfgChild,
		ManagerDirectory:       cfgManager,
		DefaultLibraryPath:     defaultLib,
		DefaultImagesDirectory: defaultDir,
		EnvOverride:            s.hasEnvOverride(),
	}
	if src != nil {
		out.EffectiveLibraryPath = src.path
	}
	if dirs.child != nil {
		out.EffectiveChildDirectory = dirs.child.path
	}
	if dirs.manager != nil {
		out.EffectiveManagerDirectory = dirs.manager.path
	}
	return out, nil
}

func (s *PictureService) require(ctx context.Context) error {
	if ctx == nil {
		return errors.New("picture service requires a context")
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if s == nil || s.Contexts == nil || s.currentSource() == nil {
		return errors.New("picture service requires owned picture library")
	}
	return nil
}

func (s *PictureService) GetMetadata(ctx context.Context, contextID, plot string) (*PictureMetadataReview, error) {
	if err := s.require(ctx); err != nil {
		return nil, err
	}
	result, err := ReadPictureMetadata(s.Contexts, ctx, contextID, plot, s.currentSource())
	if err != nil {
		return nil, err
	}
	return &result, nil
}

func (s *PictureService) GetImage(ctx context.Context, contextID, plot, requestJSON string) (*PictureImage, error) {
	if err := s.require(ctx); err != nil {
		return nil, err
	}
	var request PictureImageRequest
	if err := json.Unmarshal([]byte(requestJSON), &request); err != nil {
		return nil, err
	}
	result, err := ReadPictureImage(s.Contexts, ctx, contextID, plot, s.currentSource(), s.currentDirectories(), request.View, request.Original)
	if err != nil {
		return nil, err
	}
	return &result, nil
}
