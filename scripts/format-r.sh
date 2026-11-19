#!/usr/bin/env bash
# Format R source and test files using Posit's `air` formatter when installed.
# Exits cleanly (0) with installation guidance when optional `air` is absent on PATH.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}/r"

if command -v air >/dev/null 2>&1; then
    if [[ "$#" -gt 0 ]]; then
        exec air format "$@"
    fi
    exec air format R tests
fi

echo "INFO: optional Posit 'air' R formatter not found on PATH; skipping R format step." >&2
echo "      Install 'air' from https://posit-dev.github.io/air/ to enforce r/air.toml formatting locally." >&2
exit 0
