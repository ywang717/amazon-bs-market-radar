#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
mkdir -p "$PROJECT_ROOT/.local/powershell" "$PROJECT_ROOT/.local/node"
echo "macOS runtime directories prepared under $PROJECT_ROOT/.local"
echo "Install Homebrew first, then run: brew install node powershell postgresql@16"
echo "Chromium is installed by Playwright with: cd web && npm exec playwright install chromium"
