#!/usr/bin/env bash
# SSR Fallback: when playwright-cli network is empty, find hidden request patterns
# by fetching and grepping the site's main JS bundle.
#
# Looks for: fetch(), XMLHttpRequest, new Image().src, WebSocket connections.
# These are the patterns that bypass XHR/Fetch interception entirely.
#
# Usage (browser must be open on the target page):
#   bash inspect_ssr_requests.sh
#
# Output: matching lines from the JS source, grouped by pattern type.

echo "=== SSR Request Pattern Inspector ==="
echo "Finding main script URL from current page..."

# Use () => {} wrapper on a single line to avoid playwright-cli serialization errors
SCRIPT_URL=$(playwright-cli eval "() => { const scripts = Array.from(document.querySelectorAll('script[src]')); const main = scripts.find(s => /main|app|bundle|init/.test(s.src) && !s.src.includes('analytics') && !s.src.includes('tracking')) || scripts[scripts.length - 1]; return main ? main.src : ''; }" 2>/dev/null | grep -v "^### " | grep -v "^\- \[" | grep -v "^$" | tr -d '"' | head -1)

if [ -z "$SCRIPT_URL" ]; then
  echo "[no script found] — page may use inline scripts only, or all scripts are blocked"
  echo ""
  echo "Try manually: playwright-cli eval \"() => Array.from(document.querySelectorAll('script[src]')).map(s=>s.src)\""
  exit 1
fi

echo "Script: $SCRIPT_URL"
echo ""

# Fetch and search for request patterns
CONTENT=$(curl -sL --max-time 15 "$SCRIPT_URL" 2>/dev/null)

if [ -z "$CONTENT" ]; then
  echo "[could not fetch script — check URL or network access]"
  exit 1
fi

echo "--- fetch() calls ---"
echo "$CONTENT" | grep -oE 'fetch\([^)]{0,200}\)' | head -20 | sed 's/^/  /'

echo ""
echo "--- new Image().src side-channels ---"
echo "$CONTENT" | grep -oE '(new Image\(\)\.src|img\.src)\s*=[^;]{0,200}' | head -15 | sed 's/^/  /'

echo ""
echo "--- XMLHttpRequest ---"
echo "$CONTENT" | grep -oE 'XMLHttpRequest[^;]{0,150}' | head -10 | sed 's/^/  /'

echo ""
echo "--- WebSocket ---"
echo "$CONTENT" | grep -oE 'new WebSocket\([^)]{0,150}\)' | head -10 | sed 's/^/  /'

echo ""
echo "--- URL string patterns (heuristic — look for API paths) ---"
echo "$CONTENT" | grep -oE '"(/api/|/v[0-9]/|/graphql|/rpc/|/rest\.php/|/w/api\.php)[^"]{0,100}"' | sort -u | head -30 | sed 's/^/  /'
