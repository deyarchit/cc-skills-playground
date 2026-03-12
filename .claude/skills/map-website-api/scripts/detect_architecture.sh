#!/usr/bin/env bash
# Detects the rendering architecture of the current browser session by navigating
# to an internal link and checking whether any XHR/Fetch calls are produced.
#
# An empty log after navigation = SSR/MPA (full HTML GETs, invisible to network interception).
# A non-empty log = SPA or hybrid (client-side data fetching is visible).
#
# Usage (browser must already be open):
#   bash detect_architecture.sh <internal_url>
#   bash detect_architecture.sh https://example.com/about
#
# NOTE: playwright-cli network writes entries to a .log file; this script reads
# the file directly rather than parsing stdout (which is just a markdown pointer).

INTERNAL_URL="${1:?Usage: detect_architecture.sh <internal_url>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Architecture Detection ==="
echo "Draining network buffer..."
playwright-cli network > /dev/null 2>&1

echo "Navigating to: $INTERNAL_URL"
playwright-cli goto "$INTERNAL_URL" 2>/dev/null

# Give the page time to settle and fire any async XHR
sleep 1.5

echo ""
echo "--- Network log after navigation ---"

# Read the log file directly (not stdout, which is just a markdown pointer)
RAW=$(playwright-cli network 2>/dev/null)
LOG_FILE=$(echo "$RAW" | grep -oE '\.playwright-cli/network-[^)]+\.log' | head -1)

if [ -z "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
  RESULT=""
else
  RESULT=$(cat "$LOG_FILE" | bash "$SCRIPT_DIR/filter_noise.sh")
fi

if [ -z "$RESULT" ]; then
  echo "[EMPTY — no XHR/Fetch calls]"
  echo ""
  echo ">> Architecture: SSR / MPA"
  echo "   Full-page HTML GETs are invisible to playwright-cli network."
  echo "   This site likely uses server-side rendering for navigations."
  echo ""
  echo "   Strategy: Skip navigation flows. Focus on INTERACTIVE WIDGETS that"
  echo "   trigger in-page XHR calls: search typeahead, hover popups, carousels,"
  echo "   media viewers, infinite scroll, dynamic filters, tab switching."
  echo ""
  echo "   Also run: bash $SCRIPT_DIR/inspect_ssr_requests.sh"
  echo "   to find fetch()/XHR/Image patterns in the JS source."
else
  echo "$RESULT"
  echo ""
  echo ">> Architecture: SPA or HYBRID"
  echo "   XHR/Fetch calls are visible. Proceed with drain→act→capture loop."
  echo "   Check whether page navigations produce HTML GETs (hybrid) or only JSON (pure SPA)."
fi

echo ""
echo "--- Subdomain / third-party SPA signals ---"
# Use () => {} wrapper and single-line to avoid playwright-cli serialization errors
playwright-cli eval "() => { const s = []; document.querySelectorAll('form[action]').forEach(f => { const a = f.getAttribute('action'); if (a && (a.startsWith('http') || a.startsWith('//')) && !a.includes(location.hostname)) s.push('FORM → ' + a); }); document.querySelectorAll('iframe[src]').forEach(f => { const u = f.getAttribute('src'); if (u && !u.includes(location.hostname)) s.push('IFRAME → ' + u.split('?')[0]); }); document.querySelectorAll('a[href]').forEach(a => { const h = a.getAttribute('href'); if (h && (h.includes('auth.') || h.includes('login.') || h.includes('accounts.')) && !h.includes(location.hostname)) s.push('AUTH → ' + h.split('?')[0]); }); return s.length > 0 ? s.join('\n') : '[none detected]'; }" 2>/dev/null | grep -v "^### " | grep -v "^\- \[" | grep -v "^$" | head -20
