package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		printUsage(stderr)
		return 2
	}
	switch args[0] {
	case "build":
		return runBuild(args[1:], stdout, stderr)
	case "verify":
		return runVerify(args[1:], stdout, stderr)
	case "-h", "--help", "help":
		printUsage(stdout)
		return 0
	default:
		fmt.Fprintf(stderr, "vpro-snapshot: unknown subcommand %q\n\n", args[0])
		printUsage(stderr)
		return 2
	}
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, `Usage:
  vpro-snapshot build --source <path-to-.db-or-dir> --out <bundle-dir> [options]
  vpro-snapshot verify --bundle <bundle-dir>

Subcommands:
  build   Stage, redact (fail-closed by default), strip audit rows, finalize immutable SQLite DBs, and write manifest.json.
  verify  Verify SHA-256 hashes, immutable SQLite integrity, VP08 schema, 0-row audit tables, and sensitive coordinate redaction.`)
}

func runBuild(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("build", flag.ContinueOnError)
	fs.SetOutput(stderr)

	var opts BuildOptions
	fs.StringVar(&opts.Source, "source", "", "Path to source project .db file or directory containing .db files (required)")
	fs.StringVar(&opts.Out, "out", "", "Output bundle directory (required)")
	fs.StringVar(&opts.VLists, "vlists", "", "Optional explicit path to VP08 VLists.db")
	fs.StringVar(&opts.SupportDir, "support-dir", "", "Optional directory containing VP08 support family databases")
	fs.StringVar(&opts.SnapshotID, "snapshot-id", "", "Optional snapshot identifier (default: UTC timestamp)")
	fs.StringVar(&opts.Label, "label", "", "Optional human-readable dataset label")
	fs.BoolVar(&opts.Redact, "redact", true, "Fail-closed Red/Blue-listed species coordinate redaction (default: true)")
	fs.BoolVar(&opts.ConfirmUnredacted, "confirm-unredacted", false, "Explicit confirmation required with --redact=false to publish unredacted coordinates")
	fs.BoolVar(&opts.Force, "force", false, "Replace an existing non-empty --out bundle directory")

	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() > 0 {
		fmt.Fprintf(stderr, "vpro-snapshot build: unexpected positional arguments: %s\n", strings.Join(fs.Args(), " "))
		return 2
	}

	manifest, err := BuildSnapshot(context.Background(), opts)
	if err != nil {
		fmt.Fprintf(stderr, "vpro-snapshot build: %v\n", err)
		return 1
	}

	enc := json.NewEncoder(stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(manifest); err != nil {
		fmt.Fprintf(stderr, "vpro-snapshot build: encode output: %v\n", err)
		return 1
	}
	return 0
}

func runVerify(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("verify", flag.ContinueOnError)
	fs.SetOutput(stderr)

	var bundleDir string
	fs.StringVar(&bundleDir, "bundle", "", "Path to snapshot bundle directory containing manifest.json (required)")

	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() > 0 {
		fmt.Fprintf(stderr, "vpro-snapshot verify: unexpected positional arguments: %s\n", strings.Join(fs.Args(), " "))
		return 2
	}

	res, err := VerifyBundle(context.Background(), bundleDir)
	if err != nil {
		fmt.Fprintf(stderr, "vpro-snapshot verify: %v\n", err)
		return 1
	}

	enc := json.NewEncoder(stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(res); err != nil {
		fmt.Fprintf(stderr, "vpro-snapshot verify: encode output: %v\n", err)
		return 1
	}
	return 0
}
