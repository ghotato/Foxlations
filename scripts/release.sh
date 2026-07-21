#!/usr/bin/env bash
# One command → both artifacts in ONE builds/build-NNN/ folder:
#   1. builds the Android APK locally (bumps version, stages build-NNN + notes),
#   2. pushes the source so the iOS runner builds the SAME version,
#   3. triggers the iOS build, which scp's its .ipa back into the SAME folder.
#
#   scripts/release.sh [notes_file]
#
# Requires: the git remote set to your repo, and the GitHub CLI (`gh`) installed
# + authed (for triggering the iOS workflow). Tip: update About > What's New and
# write your notes file BEFORE running.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. Local Android build (bumps version, stages builds/build-NNN + BUILD_INFO).
scripts/build_android.sh "$@"

# 2. Build number + version just produced.
NNN=$(ls -d builds/build-* | sed 's#.*/build-##' | sort -n | tail -1)
N=$(( 10#$NNN ))
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')

# 3. Push the source so the iOS runner builds this exact version.
git add -A
git commit -m "build ${NNN} (${VERSION})" || echo "==> nothing new to commit"
git push

# 4. Trigger the iOS build → it delivers the IPA into builds/build-${NNN}/.
echo "==> Triggering iOS build ${NNN} (${VERSION})..."
gh workflow run ios-build.yml -f build_number="${N}" -f version="${VERSION}"
# No gh CLI? Trigger via the API instead (needs a PAT in $GH_TOKEN):
#   curl -X POST -H "Authorization: Bearer $GH_TOKEN" \
#     -H "Accept: application/vnd.github+json" \
#     https://api.github.com/repos/ghotato/Foxlations/actions/workflows/ios-build.yml/dispatches \
#     -d "{\"ref\":\"main\",\"inputs\":{\"build_number\":\"${N}\",\"version\":\"${VERSION}\"}}"

cat <<EOF

==> Done.
    APK: builds/build-${NNN}/  (already here)
    IPA: lands in builds/build-${NNN}/ when the iOS run finishes.
    Watch it:  gh run watch
EOF
