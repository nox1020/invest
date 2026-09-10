#!/usr/bin/env bash
# Per-boot reconciliation: ensure a virtual X display is available so the
# PySide6 desktop app (main.py) can run headless. Idempotent and returns.
set -euo pipefail

DISPLAY_NUM=":99"
LOCK="/tmp/.X99-lock"

if [ -e "${LOCK}" ] && xdpyinfo -display "${DISPLAY_NUM}" >/dev/null 2>&1; then
  echo "Xvfb already running on ${DISPLAY_NUM}"
  exit 0
fi

# Clear any stale lock from a previous boot, then start a fresh Xvfb.
rm -f "${LOCK}"
Xvfb "${DISPLAY_NUM}" -screen 0 1400x900x24 >/tmp/xvfb.log 2>&1 &

for _ in $(seq 1 20); do
  if xdpyinfo -display "${DISPLAY_NUM}" >/dev/null 2>&1; then
    echo "Xvfb ready on ${DISPLAY_NUM}"
    exit 0
  fi
  sleep 0.5
done

echo "Xvfb failed to start" >&2
cat /tmp/xvfb.log >&2 || true
exit 1
