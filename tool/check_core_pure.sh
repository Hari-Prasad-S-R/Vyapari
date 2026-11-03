#!/usr/bin/env bash
# Fails if packages/core imports Flutter or dart:io (CLAUDE.md hard rule 2).
set -euo pipefail
cd "$(dirname "$0")/.."
if grep -rnE "import ['\"](dart:io|package:flutter)" packages/core/lib; then
  echo "packages/core must stay pure Dart: remove the imports above." >&2
  exit 1
fi
echo "packages/core is pure."
