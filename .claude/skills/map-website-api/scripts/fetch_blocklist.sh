#!/usr/bin/env bash
# Downloads and caches the HaGeZi Pro ad/tracker domain blocklist.
# Stored at ~/.claude/cache/ — outside any project repo, shared across projects.
#
# The list is refreshed automatically if older than REFRESH_DAYS days.
# Safe to call before every capture session; it no-ops when the cache is fresh.
#
# Usage:
#   bash fetch_blocklist.sh          # download/refresh if stale, print cache path
#   bash fetch_blocklist.sh --force  # force re-download regardless of age
#
# Output (stdout): the path to the cached domain list file, for use in filter_noise.sh

CACHE_DIR="${HOME}/.claude/cache"
DOMAIN_FILE="${CACHE_DIR}/hagezi-ad-domains.txt"
STAMP_FILE="${CACHE_DIR}/hagezi-ad-domains.timestamp"
REFRESH_DAYS=7
SOURCE_URL="https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/pro.txt"

mkdir -p "$CACHE_DIR"

needs_refresh() {
  [ "$1" = "--force" ] && return 0
  [ ! -f "$DOMAIN_FILE" ] && return 0
  [ ! -f "$STAMP_FILE" ] && return 0
  local age_days=$(( ( $(date +%s) - $(cat "$STAMP_FILE") ) / 86400 ))
  [ "$age_days" -ge "$REFRESH_DAYS" ] && return 0
  return 1
}

if needs_refresh "$1"; then
  echo "[fetch_blocklist] Downloading HaGeZi Pro domain list (~300k entries)..." >&2
  TMP_FILE="${CACHE_DIR}/hagezi-ad-domains.tmp"

  if curl -sL --max-time 30 --fail "$SOURCE_URL" -o "$TMP_FILE" 2>/dev/null; then
    # Strip comment lines (starting with #) and blank lines, keep only domain entries
    grep -v '^#' "$TMP_FILE" | grep -v '^[[:space:]]*$' > "$DOMAIN_FILE"
    date +%s > "$STAMP_FILE"
    rm -f "$TMP_FILE"
    local_count=$(wc -l < "$DOMAIN_FILE" | tr -d ' ')
    echo "[fetch_blocklist] Cached ${local_count} domains → ${DOMAIN_FILE}" >&2
  else
    rm -f "$TMP_FILE"
    if [ -f "$DOMAIN_FILE" ]; then
      echo "[fetch_blocklist] Download failed — using existing cache (may be stale)" >&2
    else
      echo "[fetch_blocklist] Download failed and no cache exists — ad filtering will use regex fallback only" >&2
      exit 1
    fi
  fi
else
  stamp=$(cat "$STAMP_FILE")
  age_days=$(( ( $(date +%s) - stamp ) / 86400 ))
  echo "[fetch_blocklist] Cache is ${age_days}d old (refresh after ${REFRESH_DAYS}d) — skipping download" >&2
fi

echo "$DOMAIN_FILE"
