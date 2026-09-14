#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export PATH="$PROJECT_ROOT/.local/node/bin:$PROJECT_ROOT/.local/powershell:$PROJECT_ROOT/web/node_modules/.bin:$PATH"
export WRANGLER_WRITE_LOGS="${WRANGLER_WRITE_LOGS:-false}"
export WRANGLER_LOG_PATH="${WRANGLER_LOG_PATH:-$PROJECT_ROOT/.wrangler/logs}"
export MINIFLARE_REGISTRY_PATH="${MINIFLARE_REGISTRY_PATH:-$PROJECT_ROOT/.wrangler/registry}"

if [ ! -x "$PROJECT_ROOT/.local/powershell/pwsh" ]; then
  echo "PowerShell is not installed. Run: ./scripts/install-macos-runtime.sh" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  exec "$PROJECT_ROOT/.local/powershell/pwsh" -NoProfile -File "$PROJECT_ROOT/scripts/Start-LocalPackage.ps1" -Mode Test
fi

exec "$PROJECT_ROOT/.local/powershell/pwsh" -NoProfile -File "$PROJECT_ROOT/scripts/Start-LocalPackage.ps1" "$@"
