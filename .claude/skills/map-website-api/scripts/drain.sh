#!/usr/bin/env bash
# Drains the playwright-cli network buffer (discards everything captured so far).
# Call this BEFORE each action to reset the diff baseline.
#
# Usage:
#   bash drain.sh

sleep 2                                   # let in-flight calls from prior action settle
playwright-cli network > /dev/null 2>&1   # read + clear the buffer
echo "[drained]"
