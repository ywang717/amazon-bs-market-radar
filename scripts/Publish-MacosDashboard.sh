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
# launchd does not inherit terminal proxy variables. Reuse the user's macOS
# system proxy when no explicit process proxy was configured.
PROXY_PYTHON="$(command -v python3 || true)"
if [ -n "$PROXY_PYTHON" ]; then
  if [ -z "${HTTPS_PROXY:-${https_proxy:-}}" ]; then
    SYSTEM_HTTPS_PROXY="$("$PROXY_PYTHON" -c 'import urllib.request; print(urllib.request.getproxies().get("https", ""))' 2>/dev/null || true)"
    if [ -n "$SYSTEM_HTTPS_PROXY" ]; then export HTTPS_PROXY="$SYSTEM_HTTPS_PROXY"; fi
  fi
  if [ -z "${HTTP_PROXY:-${http_proxy:-}}" ]; then
    SYSTEM_HTTP_PROXY="$("$PROXY_PYTHON" -c 'import urllib.request; print(urllib.request.getproxies().get("http", ""))' 2>/dev/null || true)"
    if [ -n "$SYSTEM_HTTP_PROXY" ]; then export HTTP_PROXY="$SYSTEM_HTTP_PROXY"; fi
  fi
fi
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
