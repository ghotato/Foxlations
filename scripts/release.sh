#!/usr/bin/env bash
# One command → both artifacts in ONE builds/build-NNN/ folder:
#   1. builds the Android APK locally (bumps version, stages build-NNN + notes),
#   2. commits + pushes the source so the iOS runner builds the SAME version,
#   3. the push triggers the iOS workflow (no token needed — ios-build.yml fires
#      on a push that changes pubspec.yaml), which scp's its .ipa back into the
#      SAME folder, and finally the download page is republished.
#
#   scripts/release.sh [notes_file] [--build N] [--version X.Y.Z] [--wait]
#                      [--no-ios] [--yes]
#
# Flags:
#   --build N      pin the build number    (default: last build-NNN + 1)
#   --version X.Y.Z pin the version        (default: bump the patch)
#                  Pin BOTH if you already bumped pubspec.yaml by hand,
#                  otherwise build_android.sh bumps it a second time.
#   --wait         block until the IPA lands in builds/build-NNN/
#   --no-ios       Android only; skip commit/push/trigger
#   --yes          don't prompt before pushing
#
# Tip: update About > What's New and write your notes file BEFORE running.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WAIT=0; NO_IOS=0; ASSUME_YES=0; SITE_DIR="${FOXLATIONS_WEB_DIR:-}"; PASSTHRU=()
while [ $# -gt 0 ]; do
  case "$1" in
    --wait)    WAIT=1; shift ;;
    --no-ios)  NO_IOS=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
    --site)    SITE_DIR="$2"; shift 2 ;;
    --no-site) SITE_DIR=""; shift ;;
    *)         PASSTHRU+=("$1"); shift ;;
  esac
done

die() { echo "==> ERROR: $*" >&2; exit 1; }

# ── 0. Preflight ────────────────────────────────────────────────────────────
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "HEAD" ] && die "detached HEAD — check out a branch first"
git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote configured"

# owner/repo from the remote, so this isn't hardcoded to one fork.
SLUG=$(git remote get-url origin \
  | sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##')

# ── 1. Android build ────────────────────────────────────────────────────────
# The toolchain (Flutter, JDK, Android SDK, Rust) lives in the code-server
# CONTAINER; the TrueNAS host has none of it and can't apt-get one. But the
# host is the only side with git credentials and access to the caddy dataset.
# So when run from the host, hand just the build to the container — both see
# the same files, since /mnt/SSDs/Odysseus and /config/workspace are the same
# ZFS dataset.
BUILD_CONTAINER="${FOXLATIONS_BUILD_CONTAINER:-ix-code-server-code-server-1}"
if [ -x "${FLUTTER_BIN:-/home/coder/flutter/bin}/flutter" ] \
   || command -v flutter >/dev/null 2>&1; then
  scripts/build_android.sh ${PASSTHRU[@]+"${PASSTHRU[@]}"}
elif command -v docker >/dev/null 2>&1 \
     && docker inspect "$BUILD_CONTAINER" >/dev/null 2>&1; then
  echo "==> No local Flutter — building inside ${BUILD_CONTAINER}"
  docker exec -u coder -w /config/workspace/Test/Main "$BUILD_CONTAINER" \
    scripts/build_android.sh ${PASSTHRU[@]+"${PASSTHRU[@]}"}
else
  die "no Flutter toolchain here, and container '${BUILD_CONTAINER}' not found.
    Set FOXLATIONS_BUILD_CONTAINER, or run this from inside the container."
fi

# ── 2. What did it just produce? ────────────────────────────────────────────
NNN=$(ls -d builds/build-* 2>/dev/null | sed 's#.*/build-##' | sort -n | tail -1)
[ -n "$NNN" ] || die "no builds/build-NNN folder was produced"
OUT="builds/build-${NNN}"
N=$(cat "${OUT}/.build_number" 2>/dev/null || echo $((10#$NNN)))
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
APK=$(ls "${OUT}"/*.apk 2>/dev/null | head -1) || true
[ -n "${APK:-}" ] || die "no APK in ${OUT}"

echo
echo "==> build ${NNN}  version ${VERSION}"
echo "    APK: ${APK} ($(ls -lh "$APK" | awk '{print $5}'))"

# The notes file is copied, never generated — so running twice without editing
# it republishes the PREVIOUS release's notes to the download page, the AltStore
# manifest and the in-app update prompt. Compare against the last build's body
# (everything after BUILD_INFO's header) and say so loudly.
PREV_NNN=$(ls -d builds/build-* 2>/dev/null | sed 's#.*/build-##' | sort -n \
  | tail -2 | head -1)
if [ -n "$PREV_NNN" ] && [ "$PREV_NNN" != "$NNN" ] \
   && [ -f "builds/build-${PREV_NNN}/BUILD_INFO.txt" ]; then
  if diff -q \
      <(sed '1,/^$/d' "builds/build-${PREV_NNN}/BUILD_INFO.txt") \
      <(sed '1,/^$/d' "${OUT}/BUILD_INFO.txt") >/dev/null 2>&1; then
    echo
    echo "    ****************************************************************"
    echo "    WARNING: release notes are IDENTICAL to build ${PREV_NNN}."
    echo "    The site, AltStore and the in-app update prompt will all show"
    echo "    stale notes. Edit notes.txt before releasing."
    echo "    ****************************************************************"
    echo
  fi
fi

if [ "$NO_IOS" = "1" ]; then
  echo "==> --no-ios: stopping after the Android build."
  exit 0
fi

# ── 3. Commit + push so the runner builds this exact source ─────────────────
# Every build is supposed to bump the version AND add an About > What's New
# entry. The version bump is automatic; the changelog isn't, so warn (don't
# block) when it looks untouched.
CHANGELOG="lib/presentation/settings_screen/widgets/about_settings_page.dart"
if git diff --quiet HEAD -- "$CHANGELOG" 2>/dev/null \
   && git diff --quiet HEAD~1 HEAD -- "$CHANGELOG" 2>/dev/null; then
  echo "==> WARNING: About > What's New looks untouched (no change in the"
  echo "    working tree or the last commit) — ${CHANGELOG}"
fi

if [ "$ASSUME_YES" != "1" ]; then
  printf '==> Commit and push "%s" to %s (%s)? [y/N] ' "build ${NNN}" "$SLUG" "$BRANCH"
  read -r reply </dev/tty || reply=n
  case "$reply" in [yY]*) ;; *) die "aborted before pushing (APK is still staged in ${OUT})" ;; esac
fi

git add -A
git commit -m "build ${NNN} (${VERSION})" || echo "==> nothing new to commit"
git push -u origin "$BRANCH"

# ── 4. The iOS build ────────────────────────────────────────────────────────
# No API call, and therefore no token: ios-build.yml triggers on a push that
# changes pubspec.yaml, and step 1 always bumps the version. The push above IS
# the trigger. (Dispatching here as well would start a second, duplicate run.)
echo "==> iOS build triggered by the push (pubspec.yaml changed)."
echo "    Watch: https://github.com/${SLUG}/actions"
# ── 5. Optionally wait for the IPA to be delivered ──────────────────────────
if [ "$WAIT" = "1" ]; then
  echo "==> Waiting for the IPA to land in ${OUT}/ (Ctrl-C to stop waiting)..."
  DEADLINE=$(( $(date +%s) + 1800 ))
  while ! ls "${OUT}"/*.ipa >/dev/null 2>&1; do
    if [ "$(date +%s)" -ge "$DEADLINE" ]; then
      echo "==> Timed out after 30m. The run may still be going — check GitHub → Actions."
      break
    fi
    sleep 20
  done
  # `ls | head` exits 0 even when ls finds nothing, so test the value itself.
  IPA=$(ls "${OUT}"/*.ipa 2>/dev/null | head -1 || true)
  if [ -n "$IPA" ]; then
    echo "==> IPA delivered: ${IPA} ($(ls -lh "$IPA" | awk '{print $5}'))"
  fi
fi

# ── 6. Refresh the download page ────────────────────────────────────────────
# Runs last so it picks up the IPA too when --wait was used.
if [ -n "$SITE_DIR" ]; then
  echo "==> Publishing the download page to ${SITE_DIR}"
  scripts/publish_web.sh --build "$N" --dest "$SITE_DIR"
fi

cat <<EOF

==> Done.
    APK: ${APK}
    IPA: lands in ${OUT}/ when the iOS run finishes.
    Watch it: https://github.com/${SLUG}/actions
EOF
