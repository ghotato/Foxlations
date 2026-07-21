#!/usr/bin/env bash
# One command → both artifacts in ONE builds/build-NNN/ folder:
#   1. builds the Android APK locally (bumps version, stages build-NNN + notes),
#   2. commits + pushes the source so the iOS runner builds the SAME version,
#   3. triggers the iOS workflow, which scp's its .ipa back into the SAME folder.
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

WAIT=0; NO_IOS=0; ASSUME_YES=0; PASSTHRU=()
while [ $# -gt 0 ]; do
  case "$1" in
    --wait)    WAIT=1; shift ;;
    --no-ios)  NO_IOS=1; shift ;;
    --yes|-y)  ASSUME_YES=1; shift ;;
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

# ── 1. Local Android build ──────────────────────────────────────────────────
scripts/build_android.sh ${PASSTHRU[@]+"${PASSTHRU[@]}"}

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

# ── 4. Trigger the iOS workflow ─────────────────────────────────────────────
# The APK already exists at this point, so a failure here must NOT read as a
# failed release — report precisely what's missing and how to finish by hand.
trigger_manually() {
  cat <<EOF

==> Could not trigger the iOS build automatically: $1
    The APK is built and the source is pushed, so just start the run yourself:
      GitHub → Actions → "iOS build → server" → Run workflow
      build_number = ${N}      version = ${VERSION}
    Or set a token and re-run just the trigger:
      export GH_TOKEN=<PAT with 'actions: write'>
EOF
  exit 0
}

echo "==> Triggering iOS build ${NNN} (${VERSION})..."
if command -v gh >/dev/null 2>&1; then
  gh workflow run ios-build.yml --ref "$BRANCH" \
    -f build_number="${N}" -f version="${VERSION}" \
    || trigger_manually "gh workflow run failed"
else
  # No gh CLI on this host — use the REST API. Token, in order of preference:
  #   $GH_TOKEN / $GITHUB_TOKEN → ~/.config/foxlations/gh_token → git credential
  TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  TOKEN_FILE="${HOME}/.config/foxlations/gh_token"
  if [ -z "$TOKEN" ] && [ -r "$TOKEN_FILE" ]; then
    TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
  fi
  if [ -z "$TOKEN" ] && [ -n "$(git config --get credential.helper || true)" ]; then
    # Only safe to ask when a helper is configured; otherwise git would prompt.
    TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' \
      | git credential fill 2>/dev/null | sed -n 's/^password=//p' || true)
  fi
  [ -n "$TOKEN" ] || trigger_manually "no GitHub token found (tried \$GH_TOKEN, $TOKEN_FILE, git credential)"

  BODY=$(printf '{"ref":"%s","inputs":{"build_number":"%s","version":"%s"}}' \
    "$BRANCH" "$N" "$VERSION")
  RESP=$(mktemp)
  CODE=$(curl -sS -o "$RESP" -w '%{http_code}' -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${SLUG}/actions/workflows/ios-build.yml/dispatches" \
    -d "$BODY" || echo 000)
  if [ "$CODE" != "204" ]; then
    echo "    HTTP ${CODE}: $(head -c 400 "$RESP")" >&2
    rm -f "$RESP"
    trigger_manually "the dispatch API returned HTTP ${CODE}"
  fi
  rm -f "$RESP"
fi
echo "==> iOS build queued."

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

cat <<EOF

==> Done.
    APK: ${APK}
    IPA: lands in ${OUT}/ when the iOS run finishes.
    Watch it: https://github.com/${SLUG}/actions
EOF
