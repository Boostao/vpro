package main

import (
	"context"
	"errors"

	projectopspkg "github.com/boostao/vpro/app/internal/projectops"
	validationpkg "github.com/boostao/vpro/app/internal/validation"
)

type ValidationService struct {
	runtime  *runtimeShutdownTracker
	contexts *ContextService
}

func (s *ValidationService) acquire() (*ValidationService, func()) {
	if s == nil || s.runtime == nil {
		return s, noopRelease
	}
	snap, release := s.runtime.acquire()
	if snap == nil {
		release()
		return nil, noopRelease
	}
	return snap.validation, release
}

func NewValidationService(contexts *ContextService) *ValidationService {
	return &ValidationService{contexts: contexts}
}

func (s *ValidationService) CheckSpeciesCodes(ctx context.Context, contextID string) (SpeciesCodeCheckReview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return SpeciesCodeCheckReview{}, errors.New("validation context is unavailable")
	}
	return s.contexts.ReviewSpeciesCodes(ctx, contextID)
}

func (s *ValidationService) LookupSpeciesCodeCheckTarget(ctx context.Context, contextID string, lookup VegetationSpeciesLookup) ([]SpeciesCodeCheckOption, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return nil, errors.New("validation context is unavailable")
	}
	return s.contexts.LookupSpeciesCodeCheckTarget(ctx, contextID, lookup)
}

func (s *ValidationService) ApplySpeciesCodeCheck(contextID string, updates []SpeciesCodeCheckUpdate) error {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return errors.New("validation context is unavailable")
	}
	return s.contexts.SaveSpeciesCodeCheck(contextID, updates)
}

func (s *ValidationService) RunComplianceValidation(ctx context.Context, contextID string, opts validationpkg.ComplianceOptions) (validationpkg.ComplianceValidationReport, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return validationpkg.ComplianceValidationReport{}, errors.New("validation context is unavailable")
	}
	return s.contexts.RunComplianceValidation(ctx, contextID, opts)
}

func (s *ValidationService) QuarantineOrphanRecords(ctx context.Context, contextID string, req validationpkg.QuarantineOrphanRequest) (validationpkg.QuarantineOrphanResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return validationpkg.QuarantineOrphanResult{}, errors.New("validation context is unavailable")
	}
	return s.contexts.QuarantineOrphanRecords(ctx, contextID, req)
}

func (s *ValidationService) PreviewOptimizeVeg(ctx context.Context, contextID string, opts projectopspkg.OptimizeVegOptions) (projectopspkg.OptimizeVegPreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return projectopspkg.OptimizeVegPreview{}, errors.New("validation context is unavailable")
	}
	return s.contexts.PreviewOptimizeVeg(ctx, contextID, opts)
}

func (s *ValidationService) ApplyOptimizeVeg(ctx context.Context, contextID string, req projectopspkg.ApplyOptimizeVegRequest) (projectopspkg.OptimizeVegResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return projectopspkg.OptimizeVegResult{}, errors.New("validation context is unavailable")
	}
	return s.contexts.ApplyOptimizeVeg(ctx, contextID, req)
}

func (s *ValidationService) PreviewThreeWayMerge(ctx context.Context, contextID string, req projectopspkg.ThreeWayMergePreviewRequest) (projectopspkg.ThreeWayMergePreview, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return projectopspkg.ThreeWayMergePreview{}, errors.New("validation context is unavailable")
	}
	return s.contexts.PreviewThreeWayMerge(ctx, contextID, req)
}

func (s *ValidationService) ExecuteThreeWayMerge(ctx context.Context, contextID string, req projectopspkg.ThreeWayMergeExecuteRequest) (projectopspkg.ThreeWayMergeResult, error) {
	s, release := s.acquire()
	defer release()
	if s == nil || s.contexts == nil {
		return projectopspkg.ThreeWayMergeResult{}, errors.New("validation context is unavailable")
	}
	return s.contexts.ExecuteThreeWayMerge(ctx, contextID, req)
}
