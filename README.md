# Foxlations

A manga, manhwa, light‑novel and video reader for Android and iOS with an
extension‑based source system. Add sources from any site with the built‑in
**RepoForge** generator *(beta)*, sync progress to AniList / MyAnimeList / Kitsu,
back up and restore your library, and read behind Cloudflare‑protected sites.

> **RepoForge is in beta.** It won't always generate a correct source — check
> what it produces and adjust the selectors if a site doesn't come out right.

> Foxlations is a reader only. It does not host any content — you add your own
> sources.

## Please not that i do school and work full time, i do see your messages and issues! it just might take me a bit to get to them!

## Download

From the [**Releases**](../../releases) page, or
**[lillq.me/foxlations](https://lillq.me/foxlations)** — same builds either way:

- `foxlations-<version>-arm64.apk` — Android
- `foxlations-<version>.ipa` — iOS (unsigned, for sideloading)

iOS users can add the page's **AltStore/SideStore source** instead and get
updates automatically. The in-app **About → Check for Updates** reads the same
manifest.

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

## Privacy

Foxlations has no accounts and no analytics. It does not track you, and there is
no server holding your library — everything stays on your device. The in-app
**Stats** page (reading time, chapters read, and so on) is calculated on your
device and never leaves it.

The app only makes network requests you ask it to:

- **Sources you add** — fetched directly from those sites.
- **Update check** — when you open your library, the app asks
  `lillq.me/foxlations` whether a newer build exists. Like any web request, that
  server sees your IP address; nothing about you or your library is sent.
- **Tracking** — only if you link AniList, MyAnimeList or Kitsu. Tokens are
  encrypted on-device and sent only to that service.
- **AI translation** — only if you enable it and supply your own API key. The
  page image is sent to the provider you chose. Off by default; on-device text
  recognition needs no network at all.

## License

[Apache License 2.0](LICENSE) — see [`NOTICE`](NOTICE).

Foxlations is an independent project and is not affiliated with any content
site. It ships no sources and hosts no content.
