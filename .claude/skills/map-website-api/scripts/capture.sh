#!/usr/bin/env bash
# Captures the current playwright-cli network buffer and filters noise.
# Call this AFTER an action to see only the calls it triggered.
#
# Usage:
#   bash capture.sh "Flow: homepage feed load"
#   bash capture.sh   # label is optional
#
# Full drain→act→capture pattern:
#   bash drain.sh
#   playwright-cli goto https://example.com
#   bash capture.sh "Homepage load"
#
# NOTE: playwright-cli network writes log entries to a .log file and only puts
# a markdown pointer on stdout. This script reads the file directly.

LABEL="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$LABEL" ]; then
  echo ""
  echo "=== $LABEL ==="
fi

# Get the log file path from the playwright-cli network pointer output
RAW=$(playwright-cli network 2>/dev/null)
LOG_FILE=$(echo "$RAW" | grep -oE '\.playwright-cli/network-[^)]+\.log' | head -1)

if [ -z "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
  echo "[empty — SSR full-page load; no XHR/Fetch calls captured]"
  exit 0
fi

RESULT=$(cat "$LOG_FILE" | bash "$SCRIPT_DIR/filter_noise.sh")

if [ -z "$RESULT" ]; then
  echo "[empty after filtering — only analytics/noise (tracking, beacons); treat as SSR]"
else
  echo "$RESULT"
fi
