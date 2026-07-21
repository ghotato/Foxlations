# Foxlations

A manga, manhwa, light‑novel and video reader for Android and iOS with an
extension‑based source system. Add sources from any site with the built‑in
**RepoForge** generator, sync progress to AniList / MyAnimeList / Kitsu, back up
and restore your library, and read behind Cloudflare‑protected sites.

> Foxlations is a reader only. It does not host any content — you add your own
> sources.

## Download

Grab the latest build from the [**Releases**](../../releases) page:

- `foxlations-<version>-arm64.apk` — Android
- `foxlations-<version>.ipa` — iOS (unsigned, for sideloading)

Each release's notes list what changed in that build.

## Install — Android

1. Download the `.apk` from Releases.
2. Open it on your phone. If prompted, allow **Install unknown apps** for your
   browser/file manager.
3. Tap **Install**.

Updates: install a newer `.apk` over the old one (same signing key, so it
upgrades in place and keeps your data).

## Install — iOS (sideloading, no paid Apple account)

The iOS build is an **unsigned** `.ipa`. You sign it with your own **free Apple
ID** at install time using a sideloading tool. Pick one:

### Option A — AltStore / SideStore (recommended)
Auto‑refreshes the app so it doesn't expire on you.

1. Install [AltStore](https://altstore.io) (needs a PC/Mac companion) or
   [SideStore](https://sidestore.io) (on‑device, no computer after setup).
2. Sign in with your **free Apple ID**.
3. Download `foxlations-<version>.ipa` and open it in AltStore/SideStore →
   **Install**.

### Option B — Sideloadly (one‑off)
1. Install [Sideloadly](https://sideloadly.io) on a PC or Mac.
2. Plug in your iPhone, drag the `.ipa` in, enter your **free Apple ID**, and
   click **Start**.

### Things to know about free‑account sideloading
- Apps signed with a **free** Apple ID **expire after 7 days** and must be
  re‑signed. AltStore/SideStore do this automatically over Wi‑Fi; with
  Sideloadly you re‑run it manually.
- After installing, trust the developer profile: **Settings → General → VPN &
  Device Management → [your Apple ID] → Trust**.
- Free accounts are limited to 3 sideloaded apps at a time.
- If your device/iOS is supported by **TrollStore**, that gives a permanent
  install with no 7‑day expiry.

## Building from source

Requires the Flutter SDK and the Rust toolchain (for the `rhttp` dependency).

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64   # Android
flutter build ios --release --no-codesign                     # iOS (then package Payload/ into an .ipa)
```

Releases are produced automatically by
[`.github/workflows/release.yml`](.github/workflows/release.yml) when a `v*` tag
is pushed. To sign the Android build in CI, add these repository secrets
(base64‑encode your keystore for the first one):

`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`. Without them, CI builds a debug‑signed APK.

## Status

Source availability / license: **to be decided.** Until a license is added, all
rights are reserved.
