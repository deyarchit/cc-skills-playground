#!/usr/bin/env bash
# Filters playwright-cli network output — removes tracking, analytics, ad networks,
# and asset noise. Pipes cleanly so only data-fetching calls remain.
#
# Two-pass filtering:
#   Pass 1 — fast regex for assets, analytics, and known ad endpoint patterns
#   Pass 2 — domain blocklist (HaGeZi Pro, ~300k entries) if cached at
#             ~/.claude/cache/hagezi-ad-domains.txt
#             Run fetch_blocklist.sh once to populate. Auto-skipped if not present.
#
# Usage (pipe):
#   cat network.log | bash filter_noise.sh
#   playwright-cli network 2>/dev/null | bash filter_noise.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCKLIST="${HOME}/.claude/cache/hagezi-ad-domains.txt"

# ── Pass 1: regex filter ────────────────────────────────────────────────────
# Fast patterns: playwright-cli output headers, assets, analytics, and the most
# common ad endpoint patterns that won't appear in legitimate data APIs.
FILTER="\
^###\ \
|^\-\ \[Network\]\
|^\-\ \[Log\]\
|log_event\
|analytics\
|\/events\b\
|recaptcha\
|reporting\
|styling\
|feedback\
|\/guide\b\
|generate_204\
|jnn\/v1\
|doubleclick\
|fonts\.gstatic\
|googletagmanager\
|google-analytics\
|googleadservices\.com\
|googlesyndication\.com\
|googletagservices\.com\
|adtrafficquality\.google\
|sentry\
|mixpanel\
|amplitude\
|segment\.io\
|facebook\.com\/tr\
|\/beacon\
|\/collect\b\
|\/telemetry\
|\.woff2?\b\
|\.ttf\b\
|\.otf\b\
|\.css\b\
|\.png\b\
|\.jpg\b\
|\.jpeg\b\
|\.gif\b\
|\.svg\b\
|\.ico\b\
|\.webp\b\
|\/favicon\
|\/assets\/\
|chunk\.\
|bundle\.\
|\/openrtb2\/\
|\/cookie_sync\
|\/setuid\b\
|\/lr_sync\b\
|\/bid\/partners\/\
|\/admax\/bid\
"

# Apply pass 1
PASS1=$(grep -vEi "$FILTER")

# ── Pass 2: domain blocklist (community-maintained, 300k+ entries) ──────────
# Extracts the hostname from each log line and checks it against the blocklist.
# Gracefully skipped if the list hasn't been downloaded yet.
#
# To populate: bash fetch_blocklist.sh
if [ -f "$BLOCKLIST" ] && [ -s "$BLOCKLIST" ]; then
  # grep -vFf: fixed-string multi-pattern filter against the blocklist.
  # Each domain in the blocklist (e.g. "linkedin.com") is a substring of any URL
  # on that domain or its subdomains ("rtd.linkedin.com"), so parent-domain
  # blocking works without needing explicit subdomain expansion.
  echo "$PASS1" | grep -vFf "$BLOCKLIST"
else
  # No blocklist — output pass 1 result as-is
  # Run: bash .claude/skills/map-website-api/scripts/fetch_blocklist.sh
  # to enable community-maintained ad domain filtering (~300k domains)
  echo "$PASS1"
fi
