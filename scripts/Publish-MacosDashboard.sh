#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SECRET_PATH="$PROJECT_ROOT/.local/dashboard-sync-secret"
if [ ! -r "$SECRET_PATH" ]; then
  echo "Dashboard sync secret is missing: $SECRET_PATH" >&2
  exit 1
fi
IFS= read -r AMAZON_BS_DASHBOARD_SYNC_SECRET < "$SECRET_PATH"
export AMAZON_BS_DASHBOARD_SYNC_SECRET
export PATH="$PROJECT_ROOT/.local/node/bin:$PROJECT_ROOT/.local/powershell:$PROJECT_ROOT/web/node_modules/.bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
PWSH="$PROJECT_ROOT/.local/powershell/pwsh"
if [ ! -x "$PWSH" ]; then PWSH="$(command -v pwsh)"; fi
exec "$PWSH" -NoProfile -File "$PROJECT_ROOT/scripts/Publish-BestSellersDashboard.ps1" \
  -DashboardUrl "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/"
