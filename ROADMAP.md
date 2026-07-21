# manga_reader (Test/Main) — Roadmap & Master Plan

> Working doc for continuing **this** app (`/config/workspace/Test/Main`, pubspec name
> `manga_reader` v0.0.7+1) as the canonical codebase, and merging it with **RepoForge**
> (`/config/workspace/repoforge`) to create/manage extensions in-app.
> Written 2026-07-18. Supersedes the parallel work done in `/config/workspace/Foxlations`.

---

## 0. TL;DR / Decision

- **Build everything here, in `Test/Main`.** It is far more complete than `Foxlations`.
- `Foxlations` (v0.0.8) was a fork that **lost the vault** and re-stubbed many features.
  A lot of work was done there this session (reader loop, downloads, search, updates,
  crypto, reader settings) — but **Test/Main already has better versions of almost all of
  it**, so that work is mostly redundant. Cherry-pick only if a specific gap appears (see §8).
- The two genuinely-new goals remain:
  1. **RepoForge integration** — create sources from a URL *inside the app* (§5).
  2. **Local repos** — generate + import extension repos without GitHub (§5).
- Before any of that: **fix the build environment** (§7). It's the reason a build won't
  produce an APK out of the box in this container.

---

## 1. The three codebases

| Project | Path | What it is | State |
|---|---|---|---|
| **manga_reader** | `Test/Main` | THIS app — Hive DB, vault, anime, translation, tracking | **~95% complete** — the base going forward |
| Foxlations | `Foxlations` | Later fork, fox-themed, SharedPreferences, **no vault** | Deprecated; made functional this session but redundant |
| **RepoForge** | `repoforge` | Detects a site's CMS + selectors and **generates** reader extensions (JS) + repo index; exports ZIP or pushes to GitHub | Standalone; to be integrated/merged |

Also present (context, not in scope): `Foxations` (typo dup), `Fox-Den`, `foxlations-extensions`,
`mangayomi-main`, `mangayomi-extensions-main`, `gameforge`, `overforge`, `Overwatch`.

---

## 2. What `Test/Main` ALREADY has (don't rebuild these)

Verified by scanning `lib/`. Architecture: **Hive** (boxes + TypeAdapters) + **Provider**
(`ThemeProvider`, `SourceProvider`, `LibraryProvider`, `VaultProvider`, `DownloadProvider`,
`ReaderProvider`). Extension engine: **JS (`flutter_js`) + Dart (`d4rt`)** — Mangayomi lineage.

- **Reading loop** — library → detail → reader, real chapters, cached chapters in Hive,
  read-tracking (`readChapters`/`totalChapters`/`lastReadChapterUrl`).
- **Downloads (real)** — `core/services/download_service.dart`: fetches bytes, writes files,
  CBZ packaging (`writeAsBytes`, zip), retries. **Includes anime**: HLS/`m3u8` playlist +
  variant + segment downloading (lines ~432–470).
- **Updates (real)** — `core/services/library_update_service.dart`: `getDetail` per library
  manga, diffs against cached chapter URLs, records new chapters.
- **Global search (real)** — `presentation/global_search_screen`: real `withExtensionService`
  per source.
- **Anime watching (built)** — `presentation/player_screen/player_screen.dart` with
  **`media_kit`** + `media_kit_video`; `eval/model/m_video.dart` + `eval/dart/bridge/m_video.dart`;
  `getVideoList` wired end-to-end. `itemType: 'anime'` on sources.
- **AI translation (built)** — `google_mlkit_text_recognition` (OCR) +
  `google_mlkit_translation` + `google_generative_ai` (Gemini). ~8 files incl.
  `reader_translation_provider_sheet.dart`.
- **The Vault** — see §3. Full feature.
- **Notifications** (~7 files), **biometrics** (`local_auth`). (**Tracking** AniList/MAL is NOT
  built — audit 2026-07-18 found it UI-only/stub; see §4.1.)
- **Repos & sources** — `core/services/repo_service.dart` (parses `{repoName, repoVersion,
  sources:[...]}`), `core/models/source_model.dart` (`MangaSource`), `core/providers/source_provider.dart`,
  browse tabs incl. `repo_settings_page.dart`, `local_sources_tab_widget.dart`.
- **Reader** — `photo_view` zoom, `scrollable_positioned_list`, HUD, chapter list, settings.
- **Misc** — `webview_service.dart`, `core/utils/adblock.dart`, Cloudflare handling.

**Deps of note** (`pubspec.yaml`): `hive`/`hive_flutter`, `d4rt`, `flutter_js`, `rhttp`, `dio`,
`media_kit(+video+libs)`, `photo_view`, `google_mlkit_text_recognition`,
`google_mlkit_translation`, `google_generative_ai`, `flutter_inappwebview`, `file_picker`,
`archive`, `scrollable_positioned_list`, `path_provider`.

---

## 3. The Vault (documented so we don't lose it again)

**What it is:** a hidden, password-protected second library for stashing manga. Reached by a
secret gesture; auto-locks on backgrounding.

**Trigger** — `lib/main.dart` (the host scaffold around `AppNavigation`):
- `_libraryTapCount` / `_lastLibraryTap` count rapid taps on the **Library** tab
  (< 2000 ms apart).
- At **6–7 taps**: shows a hint snackbar ("N more taps to enter/exit vault").
- At **8 taps** (and `vault.vaultEnabled`): `_showVaultPasswordDialog` → `vault.verifyPassword` →
  `vault.enterVault()` (or `exitVault()` if already in).
- **Auto-exit** on app pause/background (`AppLifecycleState` → `context.read<VaultProvider>().exitVault()`).
- `AppNavigation` swaps the Library icon+label to **"Vault"** when `isVaultMode` is true.

**Storage** — the clever bit: `core/services/library_service.dart` is parameterized by
`prefix`: `LibraryService({String prefix = 'library'})` opens Hive boxes
`${prefix}_manga` / `${prefix}_chapters` / `${prefix}_categories`. The vault is simply a
**second instance with `prefix: 'vault'`** → completely separate boxes. Regular library and
vault never mix on disk.

**State/logic** — `core/providers/vault_provider.dart` (214 lines): `vaultEnabled`,
`vaultActive`, `hasPassword`, `verifyPassword`, `setPassword` (hashed via `_hashPassword`),
`enterVault`/`exitVault`, `vaultSourceIds` + `isSourceInVault`/`toggleVaultSource`, and full
library ops (categories, addToLibrary, reading progress, cached chapters). Settings UI:
`presentation/settings_screen/widgets/vault_settings_page.dart` (Enable Vault, Set/Change/Remove
Password).

**Polish ideas (optional):** biometric unlock for the vault (reuse `local_auth`), per-source
"move to vault" affordance in manga detail, decoy/panic behavior, hide vault sources from
global search when locked.

---

## 4. Remaining polish in `Test/Main` (small)

Most "stub" hits were false positives (placeholder widgets, slider values). Real ones:

1. **Tracking** — ⚠️ **Audit correction (2026-07-18): tracking is a STUB, not "built".**
   No service layer, no OAuth, no client IDs exist. It is UI-only:
   `manga_detail_screen.dart:340` shows a "Tracking coming soon" snackbar (`active:false`
   hardcoded); `settings_screen/widgets/tracking_settings_page.dart` hardcodes all four
   trackers to `isConnected:false` with "not yet available" snackbars. Building it requires
   **user-registered AniList/MAL API client IDs** (external app registration) before OAuth can
   work end-to-end — so this cannot be *completed* without that input.
2. `eval/javascript/service.dart:57` `getPopular not implemented` — this is the **base-class
   default** meant to be overridden by an extension (normal Mangayomi behavior), **not** a bug.
3. **Crypto/unpacker** — ✅ **DONE (2026-07-18).** Audit found these were entirely ABSENT
   (not stubbed — missing). Ported from Mangayomi into `lib/core/utils/cryptoaes/`
   (`crypto_aes.dart` / `deobfuscator.dart` / `js_unpacker.dart`) + deps `crypto` `encrypt`
   `js_packer`. Registered `cryptoHandler`/`encryptAESCryptoJS`/`decryptAESCryptoJS`/
   `deobfuscateJsPassword`/`unpackJs`/`unpackJsAndCombine` as `flutter_js` `onMessage` bridges
   in `lib/eval/javascript/utils.dart` (sync — QuickJS `sendMessage` resolves synchronously),
   plus the Mangayomi `String.prototype` helpers sources depend on. Verified at runtime via
   `tool/crypto_check.dart` (9/9). Real usage in the corpus: `unpackJs` 13 sources,
   `decryptAESCryptoJS` 3, `cryptoHandler` 2.
4. Sweep the ~18 markers and confirm none are load-bearing.

> Suggested first task: a 30-min capability audit pass to confirm 1–4 before building new stuff.

---

## 5. PRIMARY GOAL — RepoForge integration & "local repos"

**Why it's easy:** RepoForge already emits the **Mangayomi flat `index.json`** shape and JS
sources implementing `class DefaultExtension extends MProvider` with
`getPopular/search/getDetail/getPageList/getVideoList/...` — the exact contract this app runs.
And this app's `MangaSource` even carries `framework` + `config`, matching RepoForge's
framework-based generation. **No output-format change is required** — just format alignment.

### 5a. Reusable RepoForge pieces (all `repoforge/lib/services/…`, mostly pure Dart)
| File | Gives us | Notes |
|---|---|---|
| `generators/mangayomi_js_generator.dart` | Site → loadable **JS source** + index row | **Highest value.** Output already contract-compatible. |
| `framework_detector_service.dart` | Detect a site's CMS + selectors (37 frameworks) | Needs `flutter_inappwebview` (we have it) + `dio` + `html`. |
| `selector_extractor.dart` | Heuristic CSS selector extraction | Pure Dart + `html`. |
| `selector_knowledge_base.dart` + `assets/selector_kb.json` | 1220-site verified selector/theme corpus | Vendor the service + JSON asset. |
| `github_publisher.dart` | One-tap push generated source → user's GitHub repo | Optional (local repos may be enough). |
| `generators/mihon_repo_generator.dart` | Kotlin/Tachiyomi output | Skip (we run JS/Dart, not Kotlin). |

> **STATUS 2026-07-18 — §5b.1–3 DONE (local-source-only, integrated in-app).** Per user
> decision, the integrated version is **local-source only + full Scraping Studio UI**; the
> standalone RepoForge keeps GitHub publish + Mihon/other targets. Delivered:
> - **Vendored engine** (`lib/core/repoforge/`): `mangayomi_js_generator.dart`,
>   `framework_detector_service.dart` (34 frameworks, WebView+Dio), `selector_extractor.dart`,
>   `selector_knowledge_base.dart` + `assets/selector_kb.json` (1220-site KB). **Zero new pub
>   deps** — dio/html/flutter_inappwebview already present. Analyzes clean vs `flutter_inappwebview ^6.0.0`.
> - **`source_adapter.dart`** — reconciles Mangayomi row → `MangaSource` (int→String for `id`,
>   `itemType`, `sourceCodeLanguage`; carries `framework`; `additionalParams`→`config`). Verified
>   15/15 via `tool/repoforge_check.dart` (incl. anime path + fromJson survival).
> - **`local_repo_service.dart`** — writes `index.json` + `manga/src/<lang>/<pkg>.js` (relative
>   `sourceCodeUrl`) to a "My Sources" on-device repo; registers it. Install path already resolves
>   relative→local (source_manager) so **no server needed**.
> - **`repoforge_fetcher.dart`** + **Create-Source screen** (`presentation/source_creator_screen/`):
>   URL→detect→edit metadata→per-selector **live match-count testing**→JS preview→create+install.
>   Entry point: Browse ▸ Extensions tab "Create source" (✨) button; route `AppRoutes.sourceCreator`.
> - **NOT verified in-container** (needs the S24 build): the screen UI, live detection (WebView +
>   network), and end-to-end create→install→browse. Core transform is runtime-verified.
> - Skipped by design: `github_publisher.dart`, `mihon_repo_generator.dart`, ZIP/other export.

### 5b. Integration plan (phased)
1. **Vendor the engine** — copy the §5a "highest value" files into `lib/core/repoforge/`
   (generator + detector + selector_extractor + knowledge_base + `assets/selector_kb.json`).
   Reconcile RepoForge's `ext` intermediate map with our `MangaSource` (thin adapter, or teach
   the generator to emit a `MangaSource`-shaped index row directly).
2. **In-app "Create Source" flow** — new screen (e.g. `presentation/source_creator_screen/`):
   enter URL → detect framework/selectors → preview/tune (port RepoForge's Advanced Scraping
   Studio: live-test selectors, count matches) → generate JS source + index row.
3. **Local repos** — write the generated `mangayomi/`-style tree
   (`index.json` + `javascript/<pkg>.js`, with **relative** `sourceCodeUrl`) into an app folder,
   then import via the existing `repo_service.dart` / local-sources path. **Verify/implement
   relative-`sourceCodeUrl` resolution** for a local folder (remote repos resolve against the
   repo URL; local needs to resolve against the local `index.json` dir).
4. **(Optional) GitHub publish** — wire `github_publisher.dart` behind a settings toggle +
   a user PAT (stored like the tracking tokens).
5. **Merge** — once §5b.1–3 are in, RepoForge becomes a *mode* of this app ("Create/Manage
   Sources"), and RepoForge-the-standalone-app can be retired.

### 5c. Format contract to keep aligned
Index: `{ repoName, repoVersion, sources: [ MangaSource… ] }`. `MangaSource` fields (see
`core/models/source_model.dart`): `id, name, baseUrl, lang, framework, iconUrl, sourceCodeUrl,
sourceCodeLanguage(dart|js), version, isNsfw, hasCloudflare, dateFormat, dateFormatLocale,
apiUrl, appMinVerReq, config(Map), notes, repoUrl, repoName, itemType(manga|anime)`.
RepoForge's `generateIndexEntry` supplies compatible fields; map `typeSource/itemType` and set
`sourceCodeLanguage:"js"`.

---

## 6. Full backlog (everything we said we wanted)

Grouped; ✅ = already in Test/Main, ⬜ = to do/verify.

**Core reading/anime** — ✅ reader loop, ✅ downloads (manga+anime), ✅ updates, ✅ global
search, ✅ anime player, ✅ CBZ export, ✅ **PDF export** (2026-07-18: `convertToPdf` in
`download_service.dart` + mutually-exclusive `saveAsPdf` toggle in download settings;
pdf+image verified via `tool/pdf_check.dart`), ✅ **local import broadened** (2026-07-18:
single-file import of CBZ/ZIP/EPUB/PDF via `LocalSourceService.importFile` + an "Import File"
action in the Local Sources tab; **PDF pages rasterized** through `printing` — device-only;
true-RAR now detected & reported instead of silently returning `[]`). Was: images/CBZ/ZIP/EPUB
folder-scan only.

**Vault** — ✅ core feature. ⬜ optional: biometric unlock, "move to vault" in detail, hide
vault sources from search when locked (§3).

**Deferred features** — ✅ translation (ML Kit + Gemini), ✅ notifications, ✅ biometrics.
⬜ finish **tracking** UI + OAuth (§4.1; needs AniList/MAL client IDs). ⬜ verify crypto/unpacker (§4.3).

**RepoForge / sources** — ⬜ in-app source creation, ⬜ local repos, ⬜ optional GitHub publish,
⬜ retire standalone RepoForge (§5).

**Quality** — ⬜ capability-audit sweep (§4), ⬜ dead-code prune, ⬜ deprecations, ⬜ single-page
reader guards, ⬜ tests.

---

## 7. Build & run — environment setup (DO THIS FIRST)

The build fails out-of-the-box in this container for reasons that are **environmental, not code**.
All four were hit and solved for Foxlations this session; Test/Main needs the same (and it's
*heavier* — `media_kit`, ML Kit, `rhttp` pull large native deps).

1. **JDK** — none installed by default. `sudo apt-get install -y openjdk-21-jdk-headless`
   (installs to `/usr/lib/jvm/java-21-openjdk-amd64`, which Flutter is already configured for).
   Also `sudo apt-get install -y unzip xz-utils` (needed to unpack the Dart SDK).
2. **Case-insensitive filesystem** — `/config/workspace` is ZFS **`caseinsensitive`**; the
   Android NDK/CMake build CANNOT run there ("Cannot copy output executable"). `/home/coder` is
   **case-sensitive**. Fix: `flutter clean && rm -rf build && ln -s /home/coder/mangareader-build build`
   (symlink the build output to a case-sensitive dir).
3. **Memory (4 GB cgroup)** — the container is capped at 4 GB (check `/sys/fs/cgroup/memory.max`)
   and often already ~1.5–2.3 GB used. In `android/gradle.properties` set a SMALL Gradle heap so
   the Dart AOT compiler (~2–3 GB) fits:
   ```
   org.gradle.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=200m
   org.gradle.daemon=false
   org.gradle.workers.max=1
   org.gradle.parallel=false
   kotlin.daemon.jvmargs=-Xmx512m
   ```
   Before building, kill stray daemons: `pkill -9 -f KotlinCompileDaemon; pkill -9 -f GradleDaemon`.
4. **Build arm64-only** (target device is a **Samsung Galaxy S24 Ultra — arm64-v8a**): smaller
   APK + far less compile memory:
   ```
   export PATH="/home/coder/flutter/bin:$PATH"
   export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
   flutter build apk --release --target-platform android-arm64
   ```
   Note: a *late* "Gradle daemon disappeared" can appear AFTER the APK is written/signed/aligned
   (cosmetic teardown OOM). Always check for the APK anyway; verify with
   `build-tools/36.0.0/apksigner verify <apk>`.

Flutter SDK is already installed at `/home/coder/flutter` (stable 3.44.6). Android SDK at
`/home/coder/tools/android-sdk` (platform 36, build-tools 36.0.0, NDK 27/28).

**Reality check:** release AOT builds are marginal in a 4 GB box. For iterating, prefer
`flutter run`/`--debug` on a device; do release APKs arm64-only with the tuning above.

---

## 8. Cherry-pick from Foxlations? (probably not needed)

Foxlations got real implementations this session that Test/Main **already has better versions
of** (downloads, updates, search, reader loop). Only pull something over if §4 finds Test/Main
actually lacks it. Candidates, if ever needed:
- Crypto/unpacker port: `Foxlations/lib/utils/cryptoaes/{crypto_aes,deobfuscator,js_unpacker}.dart`
  (+ deps `crypto`, `encrypt`, `js_packer`) — only if Test/Main's `flutter_js` crypto is stubbed (§4.3).
- Central reader-launch helper pattern: `Foxlations/lib/services/reader_launcher.dart` — only if
  Test/Main has a reachability gap (it appears not to).
- Reader color-filter/RTL/keep-awake wiring — only if Test/Main's reader settings aren't applied.

Everything else in Foxlations (vault-less library, SharedPreferences persistence) is a step
back from Test/Main and should be ignored.

---

## 9. Suggested order of work

1. **Env setup** (§7) → get a clean `flutter run`/arm64 APK from Test/Main.
2. **Capability audit** (§4) → confirm tracking, crypto, PDF/local import; fix the small gaps.
3. **RepoForge vendor + Create-Source flow** (§5b.1–2).
4. **Local repos** (§5b.3) → generate + import without GitHub.
5. **Vault polish** (§3) + optional GitHub publish (§5b.4).
6. **Merge/retire** standalone RepoForge (§5b.5); cleanup (§6 Quality).
