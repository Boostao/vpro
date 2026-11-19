package interchange

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/sys/windows"
)

func loadPlotLabelPDFFonts(ctx context.Context) (plotLabelPDFFonts, error) {
	directory, err := windows.GetWindowsDirectory()
	if err != nil {
		return plotLabelPDFFonts{}, fmt.Errorf("runtime label font Windows directory: %w", err)
	}
	fonts, err := readPlotLabelPDFFonts(ctx, filepath.Join(directory, "Fonts"), nil)
	if err == nil {
		return fonts, nil
	}
	if ctx != nil && ctx.Err() != nil {
		return plotLabelPDFFonts{}, ctx.Err()
	}
	if errors.Is(err, os.ErrNotExist) {
		return loadBundledPlotLabelPDFFonts(ctx)
	}
	return plotLabelPDFFonts{}, err
}

func readPlotLabelPDFFonts(ctx context.Context, directory string, open func(string) (plotLabelPDFFontHandle, error)) (plotLabelPDFFonts, error) {
	if directory == "" || !filepath.IsAbs(directory) {
		return plotLabelPDFFonts{}, errors.New("runtime label fonts require an absolute system font directory")
	}
	regular, err := readPlotLabelPDFFont(ctx, filepath.Join(directory, "arial.ttf"), "ArialMT", open)
	if err != nil {
		return plotLabelPDFFonts{}, err
	}
	bold, err := readPlotLabelPDFFont(ctx, filepath.Join(directory, "arialbd.ttf"), "Arial-BoldMT", open)
	if err != nil {
		return plotLabelPDFFonts{}, err
	}
	return plotLabelPDFFonts{regular: regular, bold: bold, regularName: "ArialMT", boldName: "Arial-BoldMT"}, nil
}
