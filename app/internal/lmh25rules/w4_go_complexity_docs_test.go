package lmh25rules_test

import (
	"bytes"
	"encoding/json"
	"go/ast"
	"go/parser"
	"go/token"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boostao/vpro/app/resources"
)

func TestInternalPackagesHaveDocComments(t *testing.T) {
	appRoot := resources.RepoRoot()
	cmd := exec.Command("go", "list", "-json", "./internal/...")
	cmd.Dir = appRoot
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("go list ./internal/... failed: %v\n%s", err, string(out))
	}

	dec := json.NewDecoder(bytes.NewReader(out))
	count := 0
	var missing []string
	for {
		var pkg struct {
			ImportPath string `json:"ImportPath"`
			Name       string `json:"Name"`
			Doc        string `json:"Doc"`
		}
		if err := dec.Decode(&pkg); err != nil {
			if err == io.EOF {
				break
			}
			t.Fatalf("decode go list JSON: %v", err)
		}
		count++
		doc := strings.TrimSpace(pkg.Doc)
		wantPrefix := "Package " + pkg.Name
		if doc == "" || !strings.HasPrefix(doc, wantPrefix) {
			missing = append(missing, pkg.ImportPath+" (got doc="+doc+")")
		}
	}
	if count < 31 {
		t.Fatalf("expected at least 31 internal packages, got %d", count)
	}
	if len(missing) > 0 {
		t.Fatalf("packages missing '// Package <name> ...' doc comment:\n  %s", strings.Join(missing, "\n  "))
	}
}

func TestRefactoredHotspotsRespectComplexityAndLengthCaps(t *testing.T) {
	appRoot := resources.RepoRoot()
	targets := []string{
		"internal/lmh25rules/edatopic_keys.go",
		"internal/lmh25rules/lmh25rules.go",
		"internal/vegreport/vegetationworkbook.go",
		"internal/vegreport/vegetationlayerreport.go",
		"internal/vegreport/summaryvegetationworkbook.go",
		"internal/vegreport/summaryvegetationlayer.go",
		"internal/interchange/accessprojectimport_exec.go",
		"internal/interchange/turboveg_sqlite_read.go",
		"internal/interchange/turboveg_sqlite_write.go",
		"internal/interchange/turboveg_xml_parse.go",
		"internal/projectops/merge_execute.go",
		"internal/cloudsync/custodian_merge.go",
		"internal/validation/compliance.go",
		"internal/diagnostics/workbook.go",
		"internal/datasheet/datasheet_cell_rules.go",
		"internal/rsidecar/quarto_reports.go",
		"cmd/standards2026/taxonomy_merge.go",
	}

	fset := token.NewFileSet()
	for _, rel := range targets {
		full := filepath.Join(appRoot, rel)
		f, err := parser.ParseFile(fset, full, nil, 0)
		if err != nil {
			t.Fatalf("parse %s: %v", rel, err)
		}
		for _, decl := range f.Decls {
			fn, ok := decl.(*ast.FuncDecl)
			if !ok || fn.Body == nil {
				continue
			}
			loc := fset.Position(fn.End()).Line - fset.Position(fn.Pos()).Line + 1
			if loc > 150 {
				t.Errorf("%s:%s length = %d LOC (want <= 150)", rel, fn.Name.Name, loc)
			}
			cyclo := astCyclomaticComplexity(fn.Body)
			if cyclo > 40 {
				t.Errorf("%s:%s cyclomatic complexity = %d (want <= 40)", rel, fn.Name.Name, cyclo)
			}
		}
	}
}

func astCyclomaticComplexity(body *ast.BlockStmt) int {
	complexity := 1
	ast.Inspect(body, func(n ast.Node) bool {
		switch stmt := n.(type) {
		case *ast.IfStmt, *ast.ForStmt, *ast.RangeStmt:
			complexity++
		case *ast.CaseClause:
			if stmt.List != nil {
				complexity++
			}
		case *ast.CommClause:
			if stmt.Comm != nil {
				complexity++
			}
		case *ast.BinaryExpr:
			if stmt.Op == token.LAND || stmt.Op == token.LOR {
				complexity++
			}
		}
		return true
	})
	return complexity
}
