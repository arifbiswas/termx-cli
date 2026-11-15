#!/usr/bin/env bash
# One-liner (macOS / Linux):
#   curl -fsSL https://raw.githubusercontent.com/arifbiswas/termx-cli/main/remote/install.sh | bash
set -euo pipefail
REPO="${TERMX_REPO:-arifbiswas/termx-cli}"
BRANCH="${TERMX_BRANCH:-main}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://raw.githubusercontent.com/$REPO/$BRANCH/src/unix/termx" -o "$TMP/termx"
bash "$TMP/termx" install "$@"
