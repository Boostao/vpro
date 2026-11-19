package main

import (
	"context"
	"encoding/json"
	"errors"

	picturespkg "github.com/boostao/vpro/app/internal/pictures"
	vprocorepkg "github.com/boostao/vpro/app/internal/vprocore"
)

type PictureOptions = picturespkg.PictureOptions
type PictureOptionsUpdate = picturespkg.PictureOptionsUpdate
type PictureMetadataEdit = picturespkg.PictureMetadataEdit

type PictureService struct {
	runtime *runtimeShutdownTracker
	core    *picturespkg.PictureService
}

func (s *PictureService) acquire() (*PictureService, func()) {
	if s == nil || s.runtime == nil {
		return s, noopRelease
	}
	snap, release := s.runtime.acquire()
	if snap == nil {
		release()
		return nil, noopRelease
	}
	return snap.pictures, release
}

func unwrapPictureService(s *PictureService) *picturespkg.PictureService {
	if s == nil {
		return nil
	}
	if s.runtime != nil {
		snap, release := s.runtime.acquire()
		defer release()
		if snap == nil || snap.pictures == nil {
			return nil
		}
		return snap.pictures.core
	}
	return s.core
}

func NewPictureMetadataService(s *PictureService) (*picturespkg.PictureMetadataService, error) {
	return picturespkg.NewPictureMetadataService(unwrapPictureService(s))
}

func NewPictureCreationService(s *PictureService) (*picturespkg.PictureCreationService, error) {
	return picturespkg.NewPictureCreationService(unwrapPictureService(s))
}

func NewPictureDeletionService(s *PictureService) (*picturespkg.PictureDeletionService, error) {
	return picturespkg.NewPictureDeletionService(unwrapPictureService(s))
}

func buildPictureService(contexts *ContextService, dataDir string, baseLookup func(string) (string, bool)) (*PictureService, error) {
	defaultVPicsPath, defaultImagesDir, err := vprocorepkg.EnsureDefaultPictureLibrary(dataDir)
	if err != nil {
		return nil, err
	}
	if baseLookup == nil {
		baseLookup = func(string) (string, bool) { return "", false }
	}
	core, err := picturespkg.NewPictureServiceWithDefaults(unwrapContextService(contexts), baseLookup, defaultVPicsPath, defaultImagesDir)
	if err != nil {
		return nil, err
	}
	svc := &PictureService{core: core}
	metadata, err := NewPictureMetadataService(svc)
	if err != nil {
		return nil, err
	}
	creation, err := NewPictureCreationService(svc)
	if err != nil {
		return nil, err
	}
	deletion, err := NewPictureDeletionService(svc)
	if err != nil {
		return nil, err
	}
	svc.core.Metadata = metadata
	svc.core.Creation = creation
	svc.core.Deletion = deletion
	return svc, nil
}

func marshalTypedRPCRequest(v any) (string, error) {
	raw, err := json.Marshal(v)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

func (s *PictureService) GetPictureOptions(ctx context.Context) (*PictureOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("picture service is unavailable")
	}
	return s.core.GetPictureOptions(ctx)
}

func (s *PictureService) SavePictureOptions(ctx context.Context, update PictureOptionsUpdate) (*PictureOptions, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("picture service is unavailable")
	}
	return s.core.SavePictureOptions(ctx, update)
}

func (s *PictureService) GetMetadata(ctx context.Context, contextID, plot string) (*PictureMetadataReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("picture service is unavailable")
	}
	return s.core.GetMetadata(ctx, contextID, plot)
}

func (s *PictureService) GetImage(ctx context.Context, contextID, plot, requestJSON string) (*PictureImage, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil {
		return nil, errors.New("picture service is unavailable")
	}
	return s.core.GetImage(ctx, contextID, plot, requestJSON)
}

func (s *PictureService) SaveMetadata(ctx context.Context, contextID, plot string, request PictureMetadataEdit) (*PictureMetadataWriteResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Metadata == nil {
		return nil, errors.New("picture metadata service is unavailable")
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return nil, err
	}
	return s.core.SaveMetadata(ctx, contextID, plot, raw)
}

func (s *PictureService) LookupMetadataReceipt(ctx context.Context, contextID, plot string, request PictureMetadataEdit) (*PictureMetadataWriteResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Metadata == nil {
		return nil, errors.New("picture metadata service is unavailable")
	}
	raw, err := marshalTypedRPCRequest(request)
	if err != nil {
		return nil, err
	}
	return s.core.LookupMetadataReceipt(ctx, contextID, plot, raw)
}

func (s *PictureService) ChooseCreationImage(ctx context.Context, contextID, project, plot string) (*PictureCreationSelection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.core.ChooseCreationImage(ctx, contextID, project, plot)
}

func (s *PictureService) GetSelectedCreationImage(ctx context.Context, token, requestJSON string) (*PictureImage, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.core.GetSelectedCreationImage(ctx, token, requestJSON)
}

func (s *PictureService) RecoverCreationSelection(ctx context.Context, contextID, project, plot string) (*PictureCreationSelection, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.core.RecoverCreationSelection(ctx, contextID, project, plot)
}

func (s *PictureService) ReleaseCreationSelection(ctx context.Context, token string) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Creation == nil {
		return errors.New("picture creation service is unavailable")
	}
	return s.core.ReleaseCreationSelection(ctx, token)
}

func (s *PictureService) CreatePicture(ctx context.Context, token, requestJSON string) (*PictureCreationResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.core.CreatePicture(ctx, token, requestJSON)
}

func (s *PictureService) LookupCreationReceipt(ctx context.Context, requestJSON string) (*PictureCreationResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Creation == nil {
		return nil, errors.New("picture creation service is unavailable")
	}
	return s.core.LookupCreationReceipt(ctx, requestJSON)
}

func (s *PictureService) AcknowledgeCreationReceipt(ctx context.Context, token string) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Creation == nil {
		return errors.New("picture creation service is unavailable")
	}
	return s.core.AcknowledgeCreationReceipt(ctx, token)
}

func (s *PictureService) DeletePicture(ctx context.Context, contextID, requestJSON string) (*PictureDeletionResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.core.DeletePicture(ctx, contextID, requestJSON)
}

func (s *PictureService) GetDeletionHistory(ctx context.Context, contextID, plot string) (*PictureDeletionHistoryList, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.core.GetDeletionHistory(ctx, contextID, plot)
}

func (s *PictureService) LookupDeletionReceipt(ctx context.Context, contextID, requestJSON string) (*PictureDeletionResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.core.LookupDeletionReceipt(ctx, contextID, requestJSON)
}

func (s *PictureService) LookupDeletionRestorationReceipt(ctx context.Context, contextID, requestJSON string) (*PictureRestorationResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.core.LookupDeletionRestorationReceipt(ctx, contextID, requestJSON)
}

func (s *PictureService) ReviewDeletionRestoration(ctx context.Context, contextID, plot, historyID string) (*PictureRestorationReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.core.ReviewDeletionRestoration(ctx, contextID, plot, historyID)
}

func (s *PictureService) RestoreDeletedPicture(ctx context.Context, contextID, requestJSON string) (*PictureRestorationResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.core == nil || s.core.Deletion == nil {
		return nil, errors.New("picture deletion service is unavailable")
	}
	return s.core.RestoreDeletedPicture(ctx, contextID, requestJSON)
}
