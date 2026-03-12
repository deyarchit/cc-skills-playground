#!/usr/bin/env bash
# Drains the playwright-cli network buffer (discards everything captured so far).
# Call this BEFORE each action to reset the diff baseline.
#
# Usage:
#   bash drain.sh

playwright-cli network > /dev/null 2>&1
echo "[drained]"
