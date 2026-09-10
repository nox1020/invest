#!/usr/bin/env bash
# Idempotent Cloud Agent bootstrap for the V+ repo.
#
# Two products live here:
#   1. Python + PySide6 desktop app (main.py, app/, tests/)
#   2. Flutter Android app (lib/, test/, android/)
#
# This script installs system + language dependencies for both so that
# `pytest`, `flutter test`, `flutter analyze` and the desktop GUI all run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_HOME="/opt/flutter-sdk/flutter"

echo "==> Installing system packages (Qt/xcb, Xvfb, build tools)"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  git curl unzip xz-utils ca-certificates \
  python3-venv python3-dev build-essential \
  xvfb x11-utils imagemagick \
  libegl1 libgl1 libglib2.0-0 libdbus-1-3 \
  libxkbcommon0 libxkbcommon-x11-0 \
  libxcb1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
  libxcb-randr0 libxcb-render0 libxcb-render-util0 libxcb-shape0 libxcb-shm0 \
  libxcb-sync1 libxcb-util1 libxcb-xfixes0 libxcb-xinerama0 libxcb-xkb1 \
  libxcb-glx0 libxcb-present0 libxcb-dri2-0 libxcb-dri3-0 \
  libfontconfig1 libfreetype6 libx11-6 libx11-xcb1 libxext6 libxrender1 \
  libnss3 libxdamage1 libxrandr2 libxcomposite1 libxcursor1 libxi6 libxtst6

echo "==> Python virtualenv + dependencies"
cd "$REPO_DIR"
if [ ! -x ".venv/bin/python" ]; then
  python3 -m venv .venv
fi
.venv/bin/python -m pip install --upgrade pip
.venv/bin/pip install -r requirements.txt -r requirements-dev.txt

echo "==> Flutter SDK"
if [ ! -x "${FLUTTER_HOME}/bin/flutter" ]; then
  sudo mkdir -p "$(dirname "${FLUTTER_HOME}")"
  sudo chown -R "$(id -u):$(id -g)" "$(dirname "${FLUTTER_HOME}")"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "${FLUTTER_HOME}"
fi
git config --global --add safe.directory "${FLUTTER_HOME}" || true
git config --global --add safe.directory "${REPO_DIR}" || true
# Expose flutter/dart on PATH for every shell.
sudo ln -sf "${FLUTTER_HOME}/bin/flutter" /usr/local/bin/flutter
sudo ln -sf "${FLUTTER_HOME}/bin/dart" /usr/local/bin/dart

echo "==> flutter pub get"
"${FLUTTER_HOME}/bin/flutter" --version
"${FLUTTER_HOME}/bin/flutter" pub get
# `flutter pub get` rewrites analysis_options.yaml; keep the repo copy pristine.
git -C "${REPO_DIR}" checkout -- analysis_options.yaml 2>/dev/null || true

echo "==> Bootstrap complete"
