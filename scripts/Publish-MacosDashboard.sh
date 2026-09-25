#!/bin/sh
set -eu

PROJECT_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SECRET_PATH="$PROJECT_ROOT/.local/dashboard-sync-secret"
if [ ! -r "$SECRET_PATH" ]; then
  echo "Dashboard sync secret is missing: $SECRET_PATH" >&2
  exit 1
fi
AMAZON_BS_DASHBOARD_SYNC_SECRET="$(< "$SECRET_PATH")"
export AMAZON_BS_DASHBOARD_SYNC_SECRET
export PATH="$PROJECT_ROOT/.local/node/bin:$PROJECT_ROOT/.local/powershell:$PROJECT_ROOT/web/node_modules/.bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
PWSH="$PROJECT_ROOT/.local/powershell/pwsh"
if [ ! -x "$PWSH" ]; then PWSH="$(command -v pwsh)"; fi
LATEST_RECEIPT="$(find "$PROJECT_ROOT/var/amazon-bestsellers" -mindepth 2 -maxdepth 2 -type f -name 'best-sellers-capture-receipt.json' -print 2>/dev/null | LC_ALL=C sort | tail -n 1)"
if [ -z "$LATEST_RECEIPT" ]; then
  echo "No completed market snapshot receipt found under $PROJECT_ROOT/var/amazon-bestsellers" >&2
  exit 1
fi
MARKET_DATE="$(basename "$(dirname "$LATEST_RECEIPT")")"
exec "$PWSH" -NoProfile -File "$PROJECT_ROOT/scripts/Publish-BestSellersDashboard.ps1" \
  -DashboardUrl "https://amazon-bs-market-radar-pacific.warrenwangyihao.chatgpt.site/" \
  -MarketDate "$MARKET_DATE"
