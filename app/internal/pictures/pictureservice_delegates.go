package pictures

import (
	"context"
	"errors"
	"strings"
	"unicode/utf8"

	"github.com/boostao/vpro/app/internal/vprocore"
)

func (s *PictureService) GetPictureOptions(ctx context.Context) (*PictureOptions, error) {
	if err := s.require(ctx); err != nil {
		return nil, err
	}
	return s.buildOptionsSnapshot()
}

func (s *PictureService) SavePictureOptions(ctx context.Context, update PictureOptionsUpdate) (*PictureOptions, error) {
	if err := s.require(ctx); err != nil {
		return nil, err
	}
	if s.Contexts.Projects == nil || s.Contexts.Projects.Preferences == nil {
		return nil, errors.New("picture preferences storage is unavailable")
	}
	for _, raw := range []string{update.PictureLibraryPath, update.ChildDirectory, update.ManagerDirectory} {
		if !utf8.ValidString(raw) || strings.ContainsRune(raw, 0) {
			return nil, errors.New("picture paths must be valid Unicode text without NUL characters")
		}
	}
	libPath := strings.TrimSpace(update.PictureLibraryPath)
	childDir := strings.TrimSpace(update.ChildDirectory)
	managerDir := strings.TrimSpace(update.ManagerDirectory)

	if err := s.checkIdleForReconfigure(); err != nil {
		return nil, err
	}
	if libPath != "" {
		candidate, err := newOwnedPictureLibrary(libPath)
		if err != nil {
			return nil, err
		}
		if err := s.checkLibraryNotAliased(candidate); err != nil {
			return nil, err
		}
		if _, err := withPictureLibrarySnapshot(ctx, candidate, "", func(records vprocore.ProjectMetadataTable) (struct{}, error) {
			return struct{}{}, nil
		}); err != nil {
			return nil, err
		}
	}
	if childDir != "" {
		if _, err := newOwnedPictureDirectory(childDir); err != nil {
			return nil, err
		}
	}
	if managerDir != "" {
		if _, err := newOwnedPictureDirectory(managerDir); err != nil {
			return nil, err
		}
	}

	nextSource, nextDirs, err := s.resolveSources(libPath, childDir, managerDir)
	if err != nil {
		return nil, err
	}
	if err := s.checkLibraryNotAliased(nextSource); err != nil {
		return nil, err
	}
	if _, err := withPictureLibrarySnapshot(ctx, nextSource, "", func(records vprocore.ProjectMetadataTable) (struct{}, error) {
		return struct{}{}, nil
	}); err != nil {
		return nil, err
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if err := s.Contexts.Projects.Preferences.Update("PictureOptions", map[string]any{
		"PictureLibraryPath": libPath,
		"ChildDirectory":     childDir,
		"ManagerDirectory":   managerDir,
	}); err != nil {
		return nil, err
	}

	s.mu.Lock()
	s.source = nextSource
	s.directories = nextDirs
	s.mu.Unlock()

	return s.buildOptionsSnapshot()
}

func (s *PictureService) SaveMetadata(ctx context.Context, contextID, plot, requestJSON string) (*PictureMetadataWriteResult, error) {
	if s == nil || s.Metadata == nil {
		return nil, errors.New("picture metadata service is unavailable")
	}
	return s.Metadata.Save(ctx, contextID, plot, requestJSON)
}

func (s *PictureService) LookupMetadataReceipt(ctx context.Context, contextID, plot, requestJSON string) (*PictureMetadataWriteResult, error) {
	if s == nil || s.Metadata == nil {
		return nil, errors.New("picture metadata service is unavailable")
	}
	return s.Metadata.LookupReceipt(ctx, contextID, plot, requestJSON)
}

func (s *PictureService) ChooseCreationImage(ctx context.Context, contextID, project, plot string) (*PictureCreationSelection, error) {
	if s == nil || s.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.Creation.Choose(ctx, contextID, project, plot)
}

func (s *PictureService) GetSelectedCreationImage(ctx context.Context, token, requestJSON string) (*PictureImage, error) {
	if s == nil || s.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.Creation.GetSelectedImage(ctx, token, requestJSON)
}

func (s *PictureService) RecoverCreationSelection(ctx context.Context, contextID, project, plot string) (*PictureCreationSelection, error) {
	if s == nil || s.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.Creation.RecoverSelection(ctx, contextID, project, plot)
}

func (s *PictureService) ReleaseCreationSelection(ctx context.Context, token string) error {
	if s == nil || s.Creation == nil {
		return errors.New("picture creation service is unavailable")
	}
	return s.Creation.ReleaseSelection(ctx, token)
}

func (s *PictureService) CreatePicture(ctx context.Context, token, requestJSON string) (*PictureCreationResult, error) {
	if s == nil || s.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.Creation.Create(ctx, token, requestJSON)
}

func (s *PictureService) LookupCreationReceipt(ctx context.Context, requestJSON string) (*PictureCreationResult, error) {
	if s == nil || s.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.Creation.LookupReceipt(ctx, requestJSON)
}

func (s *PictureService) AcknowledgeCreationReceipt(ctx context.Context, token string) error {
	if s == nil || s.Creation == nil {
		return errors.New("picture creation service is unavailable")
	}
	return s.Creation.AcknowledgeReceipt(ctx, token)
}

func (s *PictureService) DeletePicture(ctx context.Context, contextID, requestJSON string) (*PictureDeletionResult, error) {
	if s == nil || s.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.Deletion.Delete(ctx, contextID, requestJSON)
}

func (s *PictureService) GetDeletionHistory(ctx context.Context, contextID, plot string) (*PictureDeletionHistoryList, error) {
	if s == nil || s.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.Deletion.GetHistory(ctx, contextID, plot)
}

func (s *PictureService) LookupDeletionReceipt(ctx context.Context, contextID, requestJSON string) (*PictureDeletionResult, error) {
	if s == nil || s.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.Deletion.LookupReceipt(ctx, contextID, requestJSON)
}

func (s *PictureService) LookupDeletionRestorationReceipt(ctx context.Context, contextID, requestJSON string) (*PictureRestorationResult, error) {
	if s == nil || s.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.Deletion.LookupRestorationReceipt(ctx, contextID, requestJSON)
}

func (s *PictureService) ReviewDeletionRestoration(ctx context.Context, contextID, plot, historyID string) (*PictureRestorationReview, error) {
	if s == nil || s.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.Deletion.ReviewRestoration(ctx, contextID, plot, historyID)
}

func (s *PictureService) RestoreDeletedPicture(ctx context.Context, contextID, requestJSON string) (*PictureRestorationResult, error) {
	if s == nil || s.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.Deletion.Restore(ctx, contextID, requestJSON)
}
