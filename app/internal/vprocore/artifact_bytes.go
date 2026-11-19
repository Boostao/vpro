package vprocore

import (
	"bytes"
	"context"
	"errors"
	"fmt"
)

// ReviewedBytesPublicationFormat constructs a deterministic ArtifactPublicationFormat
// that writes a defensive clone of expectedBytes and verifies byte-for-byte identity.
func ReviewedBytesPublicationFormat(label, artifact, commitLabel, stagePattern, mismatchMessage string, expectedBytes []byte) ArtifactPublicationFormat {
	return ArtifactPublicationFormat{
		Label:        label,
		Artifact:     artifact,
		CommitLabel:  commitLabel,
		StagePattern: stagePattern,
		Encode: func(ctx context.Context) ([]byte, error) {
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			return bytes.Clone(expectedBytes), nil
		},
		Validate: func(ctx context.Context, actual []byte) error {
			if err := ctx.Err(); err != nil {
				return err
			}
			if !bytes.Equal(actual, expectedBytes) {
				return errors.New(mismatchMessage)
			}
			return nil
		},
	}
}

// PublishReviewedWorkbookBytes publishes a reviewed XLSX workbook artifact, re-verifying
// validateSource both pre-commit and post-publish and wrapping post-publish drift with
// a non-replay warning.
func PublishReviewedWorkbookBytes(
	ctx context.Context,
	destination, label, stagePattern, mismatchMessage string,
	expectedBytes []byte,
	validateSource func() error,
	hooks ArtifactPublicationHooks,
) ArtifactPublicationReceipt {
	format := ReviewedBytesPublicationFormat(label, "XLSX", "workbook", stagePattern, mismatchMessage, expectedBytes)
	result, publishErr := PublishArtifactChecked(ctx, destination, format, validateSource, hooks)
	if result.Published {
		publishErr = errors.Join(publishErr, validateSource())
		if publishErr != nil {
			publishErr = fmt.Errorf("Workbook published; do not replay: %w", publishErr)
		}
	}
	return ArtifactPublicationOutcome(destination, result, publishErr, label)
}
