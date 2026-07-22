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

# The app-level description is what someone reads when deciding to install, so
# it's a product blurb — NOT the changelog. Per the AltStore schema the release
# notes belong on the version object instead (BUILD_INFO notes are developer
# facing and read as noise on a store page).
APP_DESC_JSON=$(printf '%s\n' \
  "One reader for manga, manhwa, manhua, light novels and video." \
  "" \
  "Add your own sources from any compatible repo, or build one for almost any site with RepoForge — no coding. Foxlations gets past Cloudflare checks, translates pages on-device, downloads chapters for offline reading, and syncs your progress to AniList, MyAnimeList or Kitsu." \
  "" \
  "Import an existing library from Tachiyomi, Mihon or Tachimanga, or bring in local .cbz/.cbr/.epub/.pdf files." \
  "" \
  "No account, no ads, nothing phoning home." \
  | json_escape)

# ── Screenshots (shared by the manifest and the page) ───────────────────────
# AltStore's field is `screenshots` — an earlier version of this script emitted
# `screenshotURLs`, which isn't in the schema and was simply ignored. A plain
# URL array is valid; width/height are only required for iPad entries.
SHOT_DIR="${DEST}/screenshots"
SHOT_FILES=""
if [ -d "$SHOT_DIR" ]; then
  SHOT_FILES=$(find "$SHOT_DIR" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
    | sort)
fi

SHOTS_JSON=""
if [ -n "$SHOT_FILES" ]; then
  shot_entries=""
  shot_sep=""
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    shot_entries="${shot_entries}${shot_sep}        \"${BASE_URL}/screenshots/$(basename "$s")\""
    shot_sep=$',\n'
  done <<< "$SHOT_FILES"
  SHOTS_JSON=$'\n      "screenshots": [\n'"${shot_entries}"$'\n      ],'
fi

# ── AltStore / SideStore source ─────────────────────────────────────────────
# Schema: https://faq.altstore.io/developers/make-a-source
#
# `appPermissions` is REQUIRED, and AltStore "will refuse to install any app
# whose permissions do not match" the downloaded IPA — so the privacy strings
# are extracted from the real ios/Runner/Info.plist rather than hardcoded here,
# where they could silently drift out of sync with what actually ships.
if [ -n "$IPA" ]; then
  PLIST="ios/Runner/Info.plist"
  PRIVACY=$(awk '
    /<key>NS[A-Za-z]+UsageDescription<\/key>/ {
      key = $0
      sub(/.*<key>/, "", key); sub(/<\/key>.*/, "", key)
      if ((getline line) > 0) {
        val = line
        sub(/.*<string>/, "", val); sub(/<\/string>.*/, "", val)
        gsub(/\\/, "\\\\", val); gsub(/"/, "\\\"", val)
        printf "%s        \"%s\": \"%s\"", sep, key, val
        sep = ",\n"
      }
    }
  ' "$PLIST" 2>/dev/null)

  # No .entitlements file exists in this project, so the list is genuinely
  # empty; team- and application-identifier are excluded by AltStore anyway.
  ENTITLEMENTS=$(grep -oE '<key>[a-z.]*com\.apple\.[A-Za-z0-9.-]+</key>' \
    ios/Runner/*.entitlements 2>/dev/null \
    | sed -E 's:.*<key>(.*)</key>:        "\1":' | paste -sd ',\n' - || true)

  cat > "${DEST}/altstore.json" <<JSON
{
  "name": "Foxlations",
  "subtitle": "Manga, manhwa, light novels and video — one reader.",
  "description": "Foxlations is one reader for manga, manhwa, manhua, light novels and video, using extension-based sources you add yourself. No account, no ads, nothing phoning home.",
  "iconURL": "${BASE_URL}/icon.png",
  "website": "${BASE_URL}",
  "tintColor": "#F97316",
  "apps": [
    {
      "name": "Foxlations",
      "bundleIdentifier": "com.foxlations.mangaReader",
      "developerName": "ghotato",
      "subtitle": "Manga, manhwa, light novels and video — one reader.",
      "localizedDescription": "${APP_DESC_JSON}",
      "iconURL": "${BASE_URL}/icon.png",
      "tintColor": "#F97316",
      "category": "entertainment",${SHOTS_JSON}
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
      ],
      "appPermissions": {
        "entitlements": [${ENTITLEMENTS:+
$ENTITLEMENTS
      }],
        "privacy": {
${PRIVACY}
        }
      }
    }
  ],
  "news": []
}
JSON
fi

# ── Screenshots (optional) ──────────────────────────────────────────────────
# Drop any images into <dest>/screenshots/ and they appear in a swipeable strip.
SHOTS_HTML=""
if [ -n "$SHOT_FILES" ]; then
  SHOTS_HTML='  <div class="shots">'$'\n'
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    SHOTS_HTML="${SHOTS_HTML}    <img src=\"screenshots/$(basename "$s")\" alt=\"Foxlations screenshot\" loading=\"lazy\">"$'\n'
  done <<< "$SHOT_FILES"
  SHOTS_HTML="${SHOTS_HTML}  </div>"
fi

# ── latest.json ─────────────────────────────────────────────────────────────
# The page reads this at load time, so the version, sizes and release notes it
# shows always reflect whatever was published last — even if index.html itself
# is an older copy. Downloads already point at the stable foxlations.apk/.ipa
# names, so those never go stale.
cat > "${DEST}/latest.json" <<JSON
{
  "version": "${SEMVER}",
  "buildNumber": "${BUILDNO}",
  "fullVersion": "${VERSION}",
  "date": "${DATE}",
  "apk": {
    "url": "foxlations.apk",
    "size": ${APK_BYTES},
    "display": "${APK_H}"
  },
  "ipa": {
    "url": "foxlations.ipa",
    "size": ${IPA_BYTES},
    "display": "${IPA_H}",
    "available": $([ -n "$IPA" ] && echo true || echo false)
  },
  "notes": "${NOTES_JSON}"
}
JSON

# ── Download page ───────────────────────────────────────────────────────────
apk_card=""
if [ -n "$APK" ]; then
  apk_card=$(cat <<CARD
      <a class="dl" id="dl-apk" data-check="foxlations.apk" href="foxlations.apk" download>
        <span class="os">Android</span>
        <span class="meta" id="apk-meta">APK · arm64 · ${APK_H}</span>
        <span class="cta">Download</span>
      </a>
CARD
)
fi
ipa_card=""
if [ -n "$IPA" ]; then
  ipa_card=$(cat <<CARD
      <a class="dl" id="dl-ipa" data-check="foxlations.ipa" href="foxlations.ipa" download>
        <span class="os">iPhone &amp; iPad</span>
        <span class="meta" id="ipa-meta">IPA · unsigned · ${IPA_H}</span>
        <span class="cta">Download</span>
      </a>
CARD
)
else
  ipa_card='      <div class="dl off"><span class="os">iPhone &amp; iPad</span><span class="meta">building…</span><span class="cta">soon</span></div>'
fi

# Only offer the AltStore source when there is actually an IPA for it to point
# at — altstore.json is written in the same branch. Showing the card without it
# would hand users a link that 404s.
alt_card=""
if [ -n "$IPA" ]; then
  # altstore://source?url=… opens AltStore and prompts to add the source,
  # rather than dumping raw JSON in the browser. Documented at
  # faq.altstore.io/altstore-classic/trusted-sources. data-check still points at
  # the manifest, since that's the thing that has to exist on the server — the
  # deep link itself can't be HEAD-checked.
  alt_card=$(cat <<CARD
    <a class="dl alt" id="dl-alt" data-check="altstore.json"
       href="altstore://source?url=${BASE_URL}/altstore.json">
      <span class="os">AltStore / SideStore</span>
      <span class="meta" id="alt-meta">opens AltStore · updates automatically</span>
      <span class="cta">Add source</span>
    </a>
    <div class="altrow">
      <a href="sidestore://source?url=${BASE_URL}/altstore.json">Open in SideStore</a>
      <button type="button" id="copy-src" data-url="${BASE_URL}/altstore.json">Copy source URL</button>
    </div>
CARD
)
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
    /* Three offset washes instead of one flat vignette — warm at the top,
       a cooler counterpoint low-left, so the page has some depth to it. */
    background:
      radial-gradient(900px 520px at 18% -8%, rgba(249,115,22,.20), transparent 62%),
      radial-gradient(760px 460px at 92% 6%, rgba(236,72,153,.10), transparent 60%),
      radial-gradient(1000px 700px at 50% 108%, rgba(124,58,237,.12), transparent 62%),
      var(--bg);
    background-attachment:fixed;
    color:var(--ink);font-family:var(--sans);line-height:1.55;min-height:100vh;
    padding:max(18px,env(safe-area-inset-top)) 14px calc(28px + env(safe-area-inset-bottom));
    -webkit-font-smoothing:antialiased;
  }
  .wrap{max-width:560px;margin:0 auto;width:100%;}
  .topbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px;}
  .back{display:inline-flex;align-items:center;gap:6px;text-decoration:none;color:var(--muted);font-size:12.5px;font-weight:600;}
  .back:hover{color:var(--ink);}
  .eyebrow{font-size:11px;letter-spacing:.32em;text-transform:uppercase;color:var(--fox);font-weight:700;margin:2px 0 10px;}
  .hero{display:flex;gap:18px;align-items:center;margin-bottom:6px;}
  /* No drop-shadow: the icon art is transparent, so a glow behind it bled out
     past the artwork and got clipped by the rounded corners. A contained tile
     with an inset hairline reads as intentional instead. */
  .hero .mark{
    width:76px;height:76px;flex:0 0 auto;border-radius:20px;display:grid;place-items:center;
    background:linear-gradient(160deg, rgba(249,115,22,.16), rgba(249,115,22,.04));
    border:1px solid rgba(249,115,22,.28);
    box-shadow:inset 0 1px 0 rgba(255,255,255,.06);
  }
  .hero .mark img{width:58px;height:58px;display:block;}
  h1{font-family:var(--serif);font-weight:600;font-style:italic;font-size:clamp(34px,10vw,48px);line-height:.98;margin:0 0 6px;letter-spacing:-.01em;}
  .sub{color:var(--muted);font-size:14px;margin:0;}
  .sub b{color:var(--ink);font-weight:600;}
  .ver{display:inline-flex;align-items:center;gap:8px;margin:18px 0 22px;font-family:var(--mono);font-size:12.5px;
    color:var(--muted);border:1px solid rgba(110,231,183,.28);border-radius:999px;padding:7px 14px;
    background:linear-gradient(180deg, rgba(110,231,183,.10), rgba(110,231,183,.03));}
  .ver b{color:var(--ink);}
  .dot{width:7px;height:7px;border-radius:50%;background:var(--mint);box-shadow:0 0 10px var(--mint);}
  .dls{display:grid;gap:10px;margin-bottom:26px;}
  .dl{position:relative;display:grid;grid-template-columns:1fr auto;grid-template-areas:"os cta" "meta cta";
    text-decoration:none;border:1px solid var(--line);border-radius:16px;
    background:linear-gradient(180deg, rgba(255,255,255,.035), rgba(255,255,255,0)) , var(--panel);
    padding:15px 16px;align-items:center;overflow:hidden;
    transition:transform .16s ease, border-color .16s ease, box-shadow .16s ease;}
  /* A warm edge-light that only appears on hover — keeps the resting state calm
     while making the primary action feel alive when reached for. */
  .dl::after{content:"";position:absolute;inset:0;border-radius:16px;pointer-events:none;
    background:radial-gradient(420px 120px at 12% 0%, rgba(249,115,22,.16), transparent 70%);
    opacity:0;transition:opacity .18s ease;}
  .dl:hover::after{opacity:1;}
  .dl:hover{box-shadow:0 12px 28px -18px rgba(249,115,22,.85);}
  .dl:hover{border-color:var(--fox);transform:translateY(-2px);}
  .dl .os{grid-area:os;font-weight:700;font-size:15.5px;color:var(--ink);position:relative;z-index:1;}
  .dl .meta{grid-area:meta;font-family:var(--mono);font-size:11.5px;color:var(--muted);position:relative;z-index:1;}
  .dl .cta{grid-area:cta;background:linear-gradient(180deg,var(--fox),var(--fox-deep));color:#fff;
    font-weight:700;font-size:13px;border-radius:10px;padding:10px 18px;position:relative;z-index:1;
    box-shadow:0 8px 18px -8px rgba(249,115,22,.9);white-space:nowrap;}
  .dl.off{opacity:.45;pointer-events:none;}
  .dl.off .cta{background:var(--panel2);color:var(--muted);box-shadow:none;border:1px solid var(--line);}
  .dl.off::after{display:none;}
  .dl.alt .cta{background:var(--panel2);color:var(--fox);border:1px solid var(--fox);box-shadow:none;}
  /* Fallbacks under the AltStore card: a custom scheme fails silently when the
     app isn't installed, so always leave a way to copy the URL by hand. */
  .altrow{display:flex;gap:14px;align-items:center;justify-content:center;margin:-2px 0 2px;}
  .altrow a,.altrow button{background:none;border:none;padding:6px 2px;cursor:pointer;
    font-family:var(--sans);font-size:12px;font-weight:600;color:var(--muted);text-decoration:none;}
  .altrow a:hover,.altrow button:hover{color:var(--fox);}
  .feat{list-style:none;padding:0;margin:0;}
  .feat li{position:relative;padding-left:20px;margin-bottom:9px;font-size:13.5px;color:var(--muted);}
  .feat li::before{content:"";position:absolute;left:2px;top:8px;width:6px;height:6px;border-radius:50%;
    background:var(--fox);box-shadow:0 0 8px rgba(249,115,22,.8);}
  .feat li b{color:var(--ink);font-weight:650;}
  .shots{display:flex;gap:10px;overflow-x:auto;padding:2px 2px 12px;margin-bottom:14px;
    scroll-snap-type:x mandatory;-webkit-overflow-scrolling:touch;}
  .shots img{height:min(64vh,460px);width:auto;border-radius:14px;border:1px solid var(--line);
    scroll-snap-align:center;flex:0 0 auto;background:var(--panel);}
  .card{position:relative;border:1px solid var(--line);border-radius:16px;padding:18px 18px 16px;margin-bottom:14px;
    background:linear-gradient(180deg, rgba(255,255,255,.03), rgba(255,255,255,0)) , var(--panel);}
  /* Hairline of colour along the top edge so stacked cards don't read as one
     undifferentiated slab. */
  .card::before{content:"";position:absolute;left:18px;right:18px;top:-1px;height:1px;
    background:linear-gradient(90deg, transparent, rgba(249,115,22,.55), transparent);}
  .card h2{font-family:var(--serif);font-style:italic;font-weight:600;font-size:21px;margin:0 0 12px;}
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
    <span class="mark"><img src="icon.png" alt="Foxlations icon"></span>
    <div>
      <div class="eyebrow">lillq.me · apps</div>
      <h1>Foxlations</h1>
    </div>
  </div>
  <p class="sub">One reader for <b>manga</b>, <b>manhwa</b>, <b>manhua</b>, <b>light novels</b> and <b>video</b> — from sources you add yourself. No account, no ads, nothing phoning home.</p>

  <div class="ver"><span class="dot"></span> Latest <b id="ver-label">v${SEMVER}</b> · <span id="ver-build">build ${BUILDNO} · ${DATE}</span></div>

  <div class="dls">
${apk_card}
${ipa_card}
${alt_card}
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
    <h2>What's new</h2>
    <div id="notes">
${NOTES_HTML}
    </div>
  </div>

  <footer id="foot">build ${NNN} · ${VERSION} · ${DATE}</footer>
</div>

<script>
// Re-read the published manifest so a cached or older index.html still shows
// the current release. Downloads use stable filenames, so only the labels here
// can drift. Everything is inserted as text — never innerHTML — so notes can't
// inject markup.
(async () => {
  try {
    const r = await fetch('latest.json?t=' + Date.now(), {cache: 'no-store'});
    if (!r.ok) return;
    const d = await r.json();
    const set = (sel, text) => {
      const el = document.querySelector(sel);
      if (el && text) el.textContent = text;
    };
    set('#ver-label', 'v' + d.version);
    set('#ver-build', 'build ' + d.buildNumber + ' · ' + d.date);
    set('#apk-meta', 'APK · arm64 · ' + (d.apk?.display || ''));
    set('#foot', 'build ' + d.buildNumber + ' · ' + d.fullVersion + ' · ' + d.date);

    if (d.ipa?.available) {
      set('#ipa-meta', 'IPA · unsigned · ' + (d.ipa.display || ''));
    }
    const notes = document.querySelector('#notes');
    if (notes && d.notes) {
      notes.replaceChildren();
      for (const line of d.notes.split('\\n')) {
        const t = line.trim();
        if (!t) continue;
        const el = document.createElement(t.startsWith('- ') ? 'li' : 'h3');
        el.textContent = t.startsWith('- ') ? t.slice(2) : t;
        notes.appendChild(el);
      }
    }
  } catch (_) {
    // Offline or manifest missing — the baked-in values stay.
  }
})();

// The page is generated from what exists on the BUILD machine, which isn't
// necessarily what reached the web server — a half-finished upload used to
// leave a Download button that 404'd (Safari reports it as "Zero KB of Zero
// KB"). HEAD each target and visibly disable anything that isn't really there.
(async () => {
  for (const el of document.querySelectorAll('[data-check]')) {
    try {
      const r = await fetch(el.dataset.check + '?t=' + Date.now(),
                            {method: 'HEAD', cache: 'no-store'});
      if (r.ok) continue;
    } catch (_) {
      // Network failure — fall through and mark it unavailable.
    }
    el.classList.add('off');
    el.removeAttribute('href');
    const cta = el.querySelector('.cta');
    if (cta) cta.textContent = 'Unavailable';
    const meta = el.querySelector('.meta');
    if (meta) meta.textContent = 'not published yet';
    // The AltStore fallbacks are meaningless without a manifest to point at.
    if (el.id === 'dl-alt') document.querySelector('.altrow')?.remove();
  }
})();

// Copy-to-clipboard for the source URL, for anyone whose device didn't pick up
// the altstore:// link (app not installed, or an in-app browser that blocks
// custom schemes).
document.querySelector('#copy-src')?.addEventListener('click', async (e) => {
  const btn = e.currentTarget;
  try {
    await navigator.clipboard.writeText(btn.dataset.url);
    const was = btn.textContent;
    btn.textContent = 'Copied';
    setTimeout(() => { btn.textContent = was; }, 1600);
  } catch (_) {
    // Clipboard blocked (non-HTTPS or denied) — show it so it can be selected.
    btn.textContent = btn.dataset.url;
  }
});
</script>
</body>
</html>
HTML

echo "==> Published build ${NNN} (${VERSION}) to ${DEST}"
[ -n "$APK" ] && echo "    APK: ${BASE_URL}/foxlations.apk (${APK_H})"
[ -n "$IPA" ] && echo "    IPA: ${BASE_URL}/foxlations.ipa (${IPA_H})"
[ -n "$IPA" ] && echo "    AltStore source: ${BASE_URL}/altstore.json"
echo "    Page: ${BASE_URL}/"
