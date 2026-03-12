#!/usr/bin/env bash
# Filters playwright-cli network output — removes tracking, analytics, and asset noise.
# Pipes cleanly so only data-fetching calls remain.
#
# Usage (pipe):
#   playwright-cli network 2>/dev/null | bash filter_noise.sh
#
# Usage (standalone, reads from stdin):
#   playwright-cli network 2>/dev/null | bash filter_noise.sh
#
# Extend FILTER by appending more patterns separated by |

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
"

grep -vEi "$FILTER"
