#!/usr/bin/env bash
# Build a release Android APK and stage it in builds/build-NNN/ with BUILD_INFO.
#   scripts/build_android.sh [notes_file] [--build N] [--version X.Y.Z]
# Standalone (no git/GitHub) — mirrors the manual per-build flow. The one-command
# orchestrator (scripts/release.sh) calls it, then triggers the iOS build.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="${HOME}/.cargo/bin:${FLUTTER_BIN:-/home/coder/flutter/bin}:${PATH}"
export CC="${CC:-cc}" CXX="${CXX:-c++}"

NOTES_FILE=""; FORCE_BUILD=""; FORCE_VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build)   FORCE_BUILD="$2"; shift 2 ;;
    --version) FORCE_VERSION="$2"; shift 2 ;;
    *)         NOTES_FILE="$1"; shift ;;
  esac
done

if [ -n "$FORCE_BUILD" ]; then
  N="$FORCE_BUILD"
else
  last=$(ls -d builds/build-* 2>/dev/null | sed 's#.*/build-##' | sort -n | tail -1 || true)
  N=$(( 10#${last:-0} + 1 ))
fi
NNN=$(printf '%03d' "$N")

cur=$(grep '^version:' pubspec.yaml | sed 's/version: //')
base=${cur%%+*}
if [ -n "$FORCE_VERSION" ]; then
  NEWVER="${FORCE_VERSION}+${N}"
else
  IFS=. read -r MA MI PA <<< "$base"
  NEWVER="${MA}.${MI}.$((PA + 1))+${N}"
fi
tmp=$(mktemp)
sed "s/^version: .*/version: ${NEWVER}/" pubspec.yaml > "$tmp" && cat "$tmp" > pubspec.yaml && rm -f "$tmp"

echo "==> Building build-${NNN}  (version ${NEWVER})"
flutter build apk --release --target-platform android-arm64

OUT="builds/build-${NNN}"
mkdir -p "$OUT"
APK="${OUT}/foxlations-${NEWVER}-arm64.apk"
cp -f build/app/outputs/flutter-apk/app-release.apk "$APK"
SIZE=$(du -h "$APK" | cut -f1)

{
  echo "Build ${NNN}"
  echo "========="
  echo "Version:  ${NEWVER}"
  echo "Date:     $(date +%Y-%m-%d)"
  echo "APK:      $(basename "$APK") (${SIZE})"
  echo "IPA:      (delivered by the iOS workflow, if run)"
  echo ""
  if [ -n "$NOTES_FILE" ] && [ -f "$NOTES_FILE" ]; then cat "$NOTES_FILE"
  else echo "(notes: fill in what changed — and update About > What's New)"; fi
} > "${OUT}/BUILD_INFO.txt"

echo "$N" > "${OUT}/.build_number"
echo "==> Staged ${APK} (${SIZE})"
echo "==> Notes:  ${OUT}/BUILD_INFO.txt"
