#!/usr/bin/env bash
# Build a release Android APK and stage it in builds/build-NNN/ with BUILD_INFO.
#   scripts/build_android.sh [notes_file] [--build N] [--version X.Y.Z]
# Standalone (no git/GitHub) — mirrors the manual per-build flow. The one-command
# orchestrator (scripts/release.sh) calls it, then triggers the iOS build.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export PATH="${HOME}/.cargo/bin:${FLUTTER_BIN:-/home/coder/flutter/bin}:${PATH}"
export CC="${CC:-cc}" CXX="${CXX:-c++}"

# Resolve a JDK rather than trusting the ambient JAVA_HOME. Gradle dies with a
# useless "JAVA_HOME is set to an invalid directory" when the path is stale —
# which happens whenever this container is recreated, since the JDK is
# apt-installed and doesn't persist while ~/.bashrc still exports the old path.
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; then
  unset JAVA_HOME
  for candidate in /usr/lib/jvm/java-21-openjdk-amd64 /usr/lib/jvm/default-java \
                   /usr/lib/jvm/*/; do
    if [ -x "${candidate%/}/bin/java" ]; then
      export JAVA_HOME="${candidate%/}"
      break
    fi
  done
fi
if [ -z "${JAVA_HOME:-}" ] && command -v java >/dev/null 2>&1; then
  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  export JAVA_HOME
fi
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; then
  echo "==> ERROR: no JDK found (JAVA_HOME=${JAVA_HOME:-unset})." >&2
  echo "    Install one:  sudo apt-get install -y openjdk-21-jdk-headless" >&2
  exit 1
fi
export PATH="${JAVA_HOME}/bin:${PATH}"

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
# The version must be written BEFORE building (flutter bakes it into the APK),
# so a failed build would otherwise leave pubspec.yaml bumped with nothing to
# show for it — and the next run would bump again from the inflated number.
# Restore it on any non-zero exit.
PUBSPEC_BACKUP=$(mktemp)
cp pubspec.yaml "$PUBSPEC_BACKUP"
trap 'rc=$?; if [ $rc -ne 0 ] && [ -s "$PUBSPEC_BACKUP" ]; then
        cp "$PUBSPEC_BACKUP" pubspec.yaml
        echo "==> build failed — pubspec.yaml version restored to $(grep "^version:" pubspec.yaml | sed "s/version: //")" >&2
      fi
      rm -f "$PUBSPEC_BACKUP"' EXIT

tmp=$(mktemp)
sed "s/^version: .*/version: ${NEWVER}/" pubspec.yaml > "$tmp" && cat "$tmp" > pubspec.yaml && rm -f "$tmp"

echo "==> Building build-${NNN}  (version ${NEWVER})"
flutter build apk --release --target-platform android-arm64

OUT="builds/build-${NNN}"
mkdir -p "$OUT"
APK="${OUT}/foxlations-${NEWVER}-arm64.apk"
cp -f build/app/outputs/flutter-apk/app-release.apk "$APK"
# NOT `du`: the builds dir is on ZFS with compression, so du reports the
# compressed on-disk size (and returns ~512 right after the copy, before blocks
# are flushed). ls gives the apparent size, which is what users download.
SIZE=$(ls -lh "$APK" | awk '{print $5}')

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
