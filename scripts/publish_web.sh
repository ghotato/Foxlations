#!/usr/bin/env bash
# Publish the newest build to the public download page at lillq.me/foxlations.
#
#   scripts/publish_web.sh [--build N] [--dest DIR] [--base-url URL]
#
# Writes into <workspace>/Sites/foxlations/ — the same place Sites/codle/ lives,
# which Caddy already serves as lillq.me/codle. Resolved RELATIVE to this repo so
# it works both on the host (/mnt/SSDs/Odysseus/...) and inside the build
# container (/config/workspace/...), which are the same ZFS dataset.
#
# Artifacts are HARD-LINKED, not copied: builds/ and Sites/ are on one dataset,
# so a 150 MB APK costs no extra space and appears instantly. (A symlink would
# dangle inside Caddy's container, which only mounts the web root.)
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$PWD"
WORKSPACE="$(cd "$REPO/../.." && pwd)"

# Destination: --dest wins, else $FOXLATIONS_WEB_DIR, else the Sites/ fallback.
# Set FOXLATIONS_WEB_DIR once (e.g. in ~/.profile) to the lillq.me web root's
# foxlations/ subdirectory — the same place the existing `disguise/` folder
# lives — and every later run publishes straight to the live site.
BUILD_N=""; DEST="${FOXLATIONS_WEB_DIR:-${WORKSPACE}/Sites/foxlations}"
BASE_URL="https://lillq.me/foxlations"
while [ $# -gt 0 ]; do
  case "$1" in
    --build)    BUILD_N="$2"; shift 2 ;;
    --dest)     DEST="$2"; shift 2 ;;
    --base-url) BASE_URL="${2%/}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

die() { echo "==> ERROR: $*" >&2; exit 1; }

# ── Locate the build to publish ─────────────────────────────────────────────
if [ -n "$BUILD_N" ]; then
  NNN=$(printf '%03d' "$BUILD_N")
else
  NNN=$(ls -d builds/build-* 2>/dev/null | sed 's#.*/build-##' | sort -n | tail -1)
fi
[ -n "${NNN:-}" ] || die "no builds/build-NNN folders found"
SRC="builds/build-${NNN}"
[ -d "$SRC" ] || die "$SRC does not exist"

APK=$(ls "$SRC"/*.apk 2>/dev/null | head -1 || true)
IPA=$(ls "$SRC"/*.ipa 2>/dev/null | head -1 || true)
[ -n "$APK" ] || [ -n "$IPA" ] || die "no .apk or .ipa in $SRC"

INFO="${SRC}/BUILD_INFO.txt"
VERSION=$(grep -m1 '^Version:' "$INFO" 2>/dev/null | awk '{print $2}' || true)
[ -n "$VERSION" ] || VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //')
DATE=$(grep -m1 '^Date:' "$INFO" 2>/dev/null | awk '{print $2}' || date +%Y-%m-%d)
SEMVER="${VERSION%%+*}"      # 0.0.26
BUILDNO="${VERSION##*+}"     # 20

mkdir -p "$DEST"

# ── Publish artifacts under stable + versioned names ────────────────────────
# link_in <src> <dest>: hardlink when possible, fall back to copy across devices
link_in() {
  rm -f "$2"
  ln "$1" "$2" 2>/dev/null || cp -f "$1" "$2"
}
APK_BYTES=0; IPA_BYTES=0; APK_H=""; IPA_H=""
if [ -n "$APK" ]; then
  link_in "$APK" "${DEST}/foxlations.apk"
  link_in "$APK" "${DEST}/foxlations-${VERSION}-arm64.apk"
  APK_BYTES=$(stat -c%s "$APK"); APK_H=$(ls -lh "$APK" | awk '{print $5}')
fi
if [ -n "$IPA" ]; then
  link_in "$IPA" "${DEST}/foxlations.ipa"
  link_in "$IPA" "${DEST}/foxlations-${VERSION}.ipa"
  IPA_BYTES=$(stat -c%s "$IPA"); IPA_H=$(ls -lh "$IPA" | awk '{print $5}')
fi
[ -f assets/images/foxlations_1024.png ] && cp -f assets/images/foxlations_1024.png "${DEST}/icon.png"

# Prune superseded versioned artifacts. If the destination is on a different
# dataset the hardlinks degrade to real copies, so without this the web root
# grows by ~200 MB per build. The stable foxlations.apk/.ipa always stay.
find "$DEST" -maxdepth 1 -type f \( -name 'foxlations-*.apk' -o -name 'foxlations-*.ipa' \) \
  ! -name "foxlations-${VERSION}-arm64.apk" ! -name "foxlations-${VERSION}.ipa" \
  -exec rm -f {} + 2>/dev/null || true

# ── Release notes ───────────────────────────────────────────────────────────
# Everything after the first blank line of BUILD_INFO.txt is the notes body.
NOTES=$(sed '1,/^$/d' "$INFO" 2>/dev/null || true)
[ -n "$NOTES" ] || NOTES="Build ${NNN}."

html_escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
# Bullets become list items; other non-empty lines become sub-headings.
NOTES_HTML=$(printf '%s\n' "$NOTES" | html_escape | awk '
  BEGIN { inlist = 0 }
  /^[[:space:]]*-[[:space:]]/ {
    if (!inlist) { print "<ul>"; inlist = 1 }
    sub(/^[[:space:]]*-[[:space:]]/, "")
    print "<li>" $0 "</li>"; next
  }
  /^[[:space:]]*$/ { if (inlist) { print "</ul>"; inlist = 0 } next }
  {
    if (inlist) { print "</ul>"; inlist = 0 }
    print "<h3>" $0 "</h3>"
  }
  END { if (inlist) print "</ul>" }
')
# JSON string: escape backslashes and quotes, then join lines with \n.
json_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r//g' | awk '{printf "%s\\n", $0}'
}
NOTES_JSON=$(printf '%s\n' "$NOTES" | json_escape)

# ── AltStore / SideStore source ─────────────────────────────────────────────
# Both the legacy top-level fields and the modern `versions` array are emitted,
# so old and current AltStore/SideStore builds can both read it.
if [ -n "$IPA" ]; then
  cat > "${DEST}/altstore.json" <<JSON
{
  "name": "Foxlations",
  "identifier": "me.lillq.foxlations",
  "subtitle": "Manga, manhwa, light novels and video — one reader.",
  "website": "${BASE_URL}",
  "tintColor": "F97316",
  "apps": [
    {
      "name": "Foxlations",
      "bundleIdentifier": "com.foxlations.mangaReader",
      "developerName": "ghotato",
      "subtitle": "Manga, manhwa, light novels and video — one reader.",
      "localizedDescription": "${NOTES_JSON}",
      "iconURL": "${BASE_URL}/icon.png",
      "tintColor": "F97316",
      "category": "entertainment",
      "screenshotURLs": [],
      "version": "${SEMVER}",
      "versionDate": "${DATE}",
      "versionDescription": "${NOTES_JSON}",
      "downloadURL": "${BASE_URL}/foxlations.ipa",
      "size": ${IPA_BYTES},
      "minOSVersion": "15.5",
      "versions": [
        {
          "version": "${SEMVER}",
          "buildVersion": "${BUILDNO}",
          "date": "${DATE}",
          "localizedDescription": "${NOTES_JSON}",
          "downloadURL": "${BASE_URL}/foxlations.ipa",
          "size": ${IPA_BYTES},
          "minOSVersion": "15.5"
        }
      ]
    }
  ],
  "news": []
}
JSON
fi

# ── Screenshots (optional) ──────────────────────────────────────────────────
# Drop any images into <dest>/screenshots/ and they appear in a swipeable strip.
SHOTS_HTML=""
SHOT_DIR="${DEST}/screenshots"
if [ -d "$SHOT_DIR" ]; then
  SHOTS=$(find "$SHOT_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
    | sort)
  if [ -n "$SHOTS" ]; then
    SHOTS_HTML='  <div class="shots">'$'\n'
    while IFS= read -r s; do
      b=$(basename "$s")
      SHOTS_HTML="${SHOTS_HTML}    <img src=\"screenshots/${b}\" alt=\"Foxlations screenshot\" loading=\"lazy\">"$'\n'
    done <<< "$SHOTS"
    SHOTS_HTML="${SHOTS_HTML}  </div>"
  fi
fi

# ── Download page ───────────────────────────────────────────────────────────
apk_card=""
if [ -n "$APK" ]; then
  apk_card=$(cat <<CARD
      <a class="dl" href="foxlations.apk" download>
        <span class="os">Android</span>
        <span class="meta">APK · arm64 · ${APK_H}</span>
        <span class="cta">Download</span>
      </a>
CARD
)
fi
ipa_card=""
if [ -n "$IPA" ]; then
  ipa_card=$(cat <<CARD
      <a class="dl" href="foxlations.ipa" download>
        <span class="os">iPhone &amp; iPad</span>
        <span class="meta">IPA · unsigned · ${IPA_H}</span>
        <span class="cta">Download</span>
      </a>
CARD
)
else
  ipa_card='      <div class="dl off"><span class="os">iPhone &amp; iPad</span><span class="meta">building…</span><span class="cta">soon</span></div>'
fi

cat > "${DEST}/index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0b0910">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="Foxlations">
<meta name="description" content="Foxlations — read manga, manhwa and light novels, and watch video, from extension-based sources. Android APK and iOS IPA downloads.">
<title>Foxlations — download</title>
<link rel="icon" href="icon.png">
<style>
  :root{
    --bg:#0b0910; --panel:#14101d; --panel2:#1b1528; --line:#2c2440;
    --ink:#ece8f7; --muted:#9a8fb4;
    --fox:#f97316; --fox-deep:#c2410c; --mint:#6ee7b7; --amber:#fbbf24;
    --serif:ui-serif,Georgia,"Times New Roman",serif;
    --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;
    --mono:ui-monospace,SFMono-Regular,Menlo,"JetBrains Mono",monospace;
  }
  *{box-sizing:border-box;}
  html,body{margin:0;padding:0;}
  body{
    background:radial-gradient(1200px 700px at 50% -10%, rgba(249,115,22,.18), transparent 60%),var(--bg);
    color:var(--ink);font-family:var(--sans);line-height:1.55;min-height:100vh;
    padding:max(18px,env(safe-area-inset-top)) 14px calc(28px + env(safe-area-inset-bottom));
    -webkit-font-smoothing:antialiased;
  }
  .wrap{max-width:560px;margin:0 auto;width:100%;}
  .topbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px;}
  .back{display:inline-flex;align-items:center;gap:6px;text-decoration:none;color:var(--muted);font-size:12.5px;font-weight:600;}
  .back:hover{color:var(--ink);}
  .eyebrow{font-size:11px;letter-spacing:.32em;text-transform:uppercase;color:var(--fox);font-weight:700;margin:2px 0 10px;}
  .hero{display:flex;gap:16px;align-items:center;margin-bottom:6px;}
  .hero img{width:72px;height:72px;border-radius:18px;box-shadow:0 14px 30px -14px rgba(249,115,22,.8);}
  h1{font-family:var(--serif);font-weight:600;font-style:italic;font-size:clamp(34px,10vw,48px);line-height:.98;margin:0 0 6px;letter-spacing:-.01em;}
  .sub{color:var(--muted);font-size:14px;margin:0;}
  .sub b{color:var(--ink);font-weight:600;}
  .ver{display:inline-flex;align-items:center;gap:8px;margin:16px 0 22px;font-family:var(--mono);font-size:12.5px;color:var(--muted);background:var(--panel);border:1px solid var(--line);border-radius:999px;padding:6px 12px;}
  .ver b{color:var(--ink);}
  .dot{width:7px;height:7px;border-radius:50%;background:var(--mint);box-shadow:0 0 10px var(--mint);}
  .dls{display:grid;gap:10px;margin-bottom:26px;}
  .dl{display:grid;grid-template-columns:1fr auto;grid-template-areas:"os cta" "meta cta";
    text-decoration:none;background:var(--panel);border:1px solid var(--line);border-radius:16px;
    padding:14px 16px;align-items:center;transition:.15s;}
  .dl:hover{border-color:var(--fox);transform:translateY(-1px);}
  .dl .os{grid-area:os;font-weight:700;font-size:15px;color:var(--ink);}
  .dl .meta{grid-area:meta;font-family:var(--mono);font-size:11.5px;color:var(--muted);}
  .dl .cta{grid-area:cta;background:linear-gradient(180deg,var(--fox),var(--fox-deep));color:#fff;
    font-weight:700;font-size:13px;border-radius:10px;padding:9px 16px;box-shadow:0 8px 18px -8px rgba(249,115,22,.9);}
  .dl.off{opacity:.5;}
  .dl.off .cta{background:var(--panel2);color:var(--muted);box-shadow:none;}
  .dl.alt .cta{background:var(--panel2);color:var(--fox);border:1px solid var(--fox);box-shadow:none;}
  .feat{list-style:none;padding:0;margin:0;}
  .feat li{position:relative;padding-left:20px;margin-bottom:9px;font-size:13.5px;color:var(--muted);}
  .feat li::before{content:"";position:absolute;left:2px;top:8px;width:6px;height:6px;border-radius:50%;
    background:var(--fox);box-shadow:0 0 8px rgba(249,115,22,.8);}
  .feat li b{color:var(--ink);font-weight:650;}
  .shots{display:flex;gap:10px;overflow-x:auto;padding:2px 2px 12px;margin-bottom:14px;
    scroll-snap-type:x mandatory;-webkit-overflow-scrolling:touch;}
  .shots img{height:min(64vh,460px);width:auto;border-radius:14px;border:1px solid var(--line);
    scroll-snap-align:center;flex:0 0 auto;background:var(--panel);}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:16px;padding:16px 18px;margin-bottom:14px;}
  .card h2{font-family:var(--serif);font-style:italic;font-weight:600;font-size:20px;margin:0 0 10px;}
  .card h3{font-size:13px;font-weight:700;color:var(--fox);margin:14px 0 6px;letter-spacing:.01em;}
  .card h3:first-child{margin-top:0;}
  .card ul{margin:0;padding-left:18px;}
  .card li{font-size:13.5px;color:var(--muted);margin-bottom:5px;}
  .card li b{color:var(--ink);}
  .card p{font-size:13.5px;color:var(--muted);margin:0 0 8px;}
  .card code{font-family:var(--mono);font-size:12px;background:var(--panel2);border:1px solid var(--line);border-radius:6px;padding:1px 6px;color:var(--ink);}
  .steps{counter-reset:s;list-style:none;padding:0;margin:0;}
  .steps li{counter-increment:s;position:relative;padding-left:30px;margin-bottom:9px;font-size:13.5px;color:var(--muted);}
  .steps li::before{content:counter(s);position:absolute;left:0;top:1px;width:20px;height:20px;border-radius:6px;
    background:var(--panel2);border:1px solid var(--line);color:var(--fox);font-family:var(--mono);font-size:11px;
    font-weight:700;display:grid;place-items:center;}
  .altbtn{display:block;text-align:center;text-decoration:none;background:var(--panel2);border:1px solid var(--fox);
    color:var(--fox);font-weight:700;font-size:13px;border-radius:12px;padding:11px;margin-top:10px;}
  .note{font-size:12px;color:var(--muted);border-left:2px solid var(--fox);padding-left:10px;margin-top:12px;}
  footer{text-align:center;color:var(--muted);font-size:11.5px;margin-top:26px;font-family:var(--mono);}
</style>
</head>
<body>
<div class="wrap">
  <div class="topbar">
    <a class="back" href="/">&#8249;&nbsp;lillq.me</a>
    <span class="back">Foxlations</span>
  </div>

  <div class="hero">
    <img src="icon.png" alt="Foxlations icon">
    <div>
      <div class="eyebrow">lillq.me · apps</div>
      <h1>Foxlations</h1>
    </div>
  </div>
  <p class="sub">One reader for <b>manga</b>, <b>manhwa</b>, <b>manhua</b>, <b>light novels</b> and <b>video</b> — from sources you add yourself. No account, no ads, nothing phoning home.</p>

  <div class="ver"><span class="dot"></span> Latest <b>v${SEMVER}</b> · build ${BUILDNO} · ${DATE}</div>

  <div class="dls">
${apk_card}
${ipa_card}
    <a class="dl alt" href="altstore.json">
      <span class="os">AltStore / SideStore</span>
      <span class="meta">source · auto-updates</span>
      <span class="cta">Add source</span>
    </a>
  </div>

  <div class="card">
    <h2>What it does</h2>
    <ul class="feat">
      <li><b>Everything in one app</b> — manga, manhwa and manhua, light novels, and video, each with a reader/player built for it.</li>
      <li><b>Your own sources</b> — install extensions from any compatible repo, or point it at a repo URL. Runs both JavaScript and Dart extensions.</li>
      <li><b>RepoForge</b> — build a working source for almost any site from inside the app, no coding. It detects the site's framework and fills in the selectors.</li>
      <li><b>Gets past Cloudflare</b> — solves the check automatically where it can, shows a quick in-app verify screen where it can't, then remembers it.</li>
      <li><b>AI translation</b> — on-device text recognition finds the speech bubbles, then translates them in place.</li>
      <li><b>Tracking</b> — link AniList, MyAnimeList or Kitsu and your chapter progress syncs as you read.</li>
      <li><b>Offline</b> — download chapters to read with no connection.</li>
      <li><b>Backup &amp; restore</b> — native backups on a schedule, plus Tachiyomi/Mihon <code>.tachibk</code> import and export so you can bring a library across.</li>
      <li><b>Global search</b> — search every installed source at once.</li>
      <li><b>Local files</b> — import <code>.cbz</code>, <code>.cbr</code>, <code>.zip</code>, <code>.epub</code> and <code>.pdf</code> straight into your library.</li>
    </ul>
  </div>
${SHOTS_HTML}
  <div class="card">
    <h2>Installing</h2>
    <h3>Android</h3>
    <ol class="steps">
      <li>Download the APK.</li>
      <li>Open it — Android will ask to allow installs from your browser.</li>
      <li>If Play Protect warns about an unknown developer, choose <b>Install anyway</b>.</li>
    </ol>
    <h3>iPhone &amp; iPad</h3>
    <p>The IPA is <b>unsigned</b>, so it has to be sideloaded. Adding the source above to AltStore or SideStore is easiest — you'll get updates automatically. To add it by hand, use <b>Browse → Sources → +</b> with:</p>
    <p><code>${BASE_URL}/altstore.json</code></p>
    <p class="note">A free Apple ID signature lasts <b>7 days</b> before the app needs re-signing; AltStore and SideStore can do that in the background. Needs iOS 15.5 or newer. You can also just download the IPA and use <b>Sideloadly</b>.</p>
  </div>

  <div class="card">
    <h2>What's new in v${SEMVER}</h2>
${NOTES_HTML}
  </div>

  <footer>build ${NNN} · ${VERSION} · ${DATE}</footer>
</div>
</body>
</html>
HTML

echo "==> Published build ${NNN} (${VERSION}) to ${DEST}"
[ -n "$APK" ] && echo "    APK: ${BASE_URL}/foxlations.apk (${APK_H})"
[ -n "$IPA" ] && echo "    IPA: ${BASE_URL}/foxlations.ipa (${IPA_H})"
[ -n "$IPA" ] && echo "    AltStore source: ${BASE_URL}/altstore.json"
echo "    Page: ${BASE_URL}/"
