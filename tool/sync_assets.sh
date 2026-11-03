#!/usr/bin/env bash
# Copies the board theme into the Flutter app bundle. assets/boards is the
# source of truth; CI checks the two match.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p packages/app/assets/boards/india
cp assets/boards/india/*.json packages/app/assets/boards/india/
echo "Synced assets/boards/india → packages/app/assets/boards/india"
