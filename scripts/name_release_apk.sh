#!/usr/bin/env bash
# Flutter always copies the release APK as app-release.apk.
# Canonical download name is invest-<versionName>.apk (e.g. invest-1.0.95.apk).
set -euo pipefail

OUT="${1:-}"
VERSION_NAME="${2:-}"
if [ -z "${OUT}" ] || [ -z "${VERSION_NAME}" ]; then
  echo "usage: $0 <flutter-apk-dir> <versionName>" >&2
  echo "example: $0 build/app/outputs/flutter-apk 1.0.95" >&2
  exit 2
fi
if [[ ! "${VERSION_NAME}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "versionName must look like 1.0.95, got: ${VERSION_NAME}" >&2
  exit 2
fi

mkdir -p "${OUT}"
DEST="${OUT}/invest-${VERSION_NAME}.apk"

pick=""
if [ -f "${DEST}" ]; then
  pick="${DEST}"
elif [ -f "${OUT}/app-release.apk" ]; then
  pick="${OUT}/app-release.apk"
else
  pick="$(ls -1t "${OUT}"/*.apk 2>/dev/null | head -n1 || true)"
fi

if [ -z "${pick}" ] || [ ! -f "${pick}" ]; then
  echo "no APK found in ${OUT}" >&2
  ls -la "${OUT}" >&2 || true
  exit 1
fi

if [ "${pick}" != "${DEST}" ]; then
  rm -f "${DEST}"
  mv -f "${pick}" "${DEST}"
fi

rm -f "${OUT}/app-release.apk"
find "${OUT}" -maxdepth 1 -type f -name '*.apk' ! -name "$(basename "${DEST}")" -delete

test -f "${DEST}"
test ! -f "${OUT}/app-release.apk"
echo "${DEST}"
