# iOS Kotlin extensions — embedded Suwayomi/JVM spike plan

Goal: run **Kotlin (Tachiyomi/Keiyoushi) extensions on-device on iOS**, the same
way Tachimanga does — a **local Suwayomi server on a bundled JVM**, bound to
`127.0.0.1`, with the Flutter UI as an HTTP client. Nothing hosted; everything in
the app. The existing Dart + JS engine (d4rt + flutter_js) stays as the
universal, lightweight baseline; Kotlin is a **second, heavier runtime**.

This is a research spike with real risk. **Do not build the Dart bridge, repo
installer, or UI until Milestone 1 passes.** If M1 or M5 fails, the fallback is
Android-native + iOS staying Dart/JS-only.

---

## Architecture (mirrors Tachimanga)

```
iOS app process
 ├─ Flutter UI  ──HTTP──▶  127.0.0.1:<port>
 └─ Embedded JVM (OpenJDK Zero, interpreter-only)
      └─ Suwayomi-Server (Ktor) on localhost
           ├─ loads Tachiyomi extension "APKs" (dex→jar + android.* shims)  ← Suwayomi already does this
           └─ exposes browse/search/chapters/pages API
```

Flutter never links the JVM directly. A tiny C/Obj-C shim starts the VM via the
**JNI Invocation API** (`JNI_CreateJavaVM`) in-process at launch, sets the
classpath to bundled jars, and calls Suwayomi's entrypoint; Suwayomi opens its
HTTP port; Dart talks to that port exactly like a remote server (but it's local).

---

## Why iOS is the hard part

Apple bans JIT: third-party apps can't allocate executable memory. Extensions are
loaded as **bytecode at runtime**, so every closed-world AOT trick is out —
GraalVM native-image, Kotlin/Wasm, RoboVM/MOE all need the full class set known at
compile time. The only route that loads arbitrary bytecode without JIT is an
**interpreter-mode JVM**.

**JVM decision: OpenJDK with the "Zero" interpreter, cross-built for ios-arm64 —
via the OFFICIAL `openjdk/mobile` project (not a from-scratch port).**
- Zero is a pure-interpreter, no-assembler OpenJDK build — no JIT, no W+X memory,
  so it doesn't violate iOS rules. It's the **default variant for iOS** in
  openjdk/mobile, which already builds a static `libjvm.a` for exactly this.
- Full Java SE class library, which Suwayomi's stack needs (Ktor, kotlinx
  coroutines, jsoup, okhttp, H2). Avian was considered and rejected: too limited a
  class library to run full Suwayomi ("like Tachimanga" = run the real server).
- Existence proofs a full JVM runs on sideloaded iOS: PojavLauncher (desktop Java /
  Minecraft on iOS), thebaselab (OpenJDK 8 on iOS). Tachimanga ships the same kind
  of interpreter JVM.
- **Grounded M0 build recipe (verified configure/make/artifact) is in
  [m0-openjdk-ios-build.md](m0-openjdk-ios-build.md).**

### Distribution insight that helps us
Foxlations is **sideloaded** (IPA + AltStore manifest over our own pipeline), not
shipped through the App Store. So:
- **App Store review guideline 2.5.2** ("don't download & execute code that
  changes features") — the classic blocker for this kind of app — **does not
  gate us**, because we don't go through review.
- **JIT is still unavailable** at the OS level regardless of sideloading (it needs
  provisioning we won't reliably have), so **interpreter mode is still required** —
  don't try to enable JIT. The win is only that the *review* barrier is gone, not
  the *runtime* one.

---

## Milestones (each has a hard pass/fail bar)

### M0 — Build the JVM for iOS
Cross-build OpenJDK **Zero** for `ios-arm64` (device) and `ios-arm64` simulator:
`libjvm.a`/`libjvm.dylib` + a trimmed module image (`jimage`/`modules`).
- Runs on: the **GitHub macOS runner** — cross-compiling for an iOS *target* needs
  the iOS SDK, which is macOS-only. The k8s cluster **cannot** build the iOS
  libjvm (no iOS SDK on Linux); it can only build the Android JVM/dex side and the
  platform-independent Suwayomi jar. Cache the built libjvm + module image as a CI
  artifact so this heavy step runs once, not every iteration.
- **Pass:** static/dynamic libjvm + module image produced, links into a throwaway
  iOS test app without missing symbols.

### M1 — Boot the VM on a real device  ← MAKE-OR-BREAK
Bare SwiftUI/UIKit app: C shim calls `JNI_CreateJavaVM`, classpath = a bundled
`HelloWorld.jar`, invoke `main`, print to a text view.
- **Pass:** `HelloWorld` runs on a physically-attached iPhone (not just the
  simulator — the simulator is x86/rosetta-lenient and doesn't prove device
  memory rules). No JIT entitlement used.
- **Fail here → STOP.** Fall back to Android-native + iOS Dart/JS-only. Nothing
  else in this plan matters if the VM can't boot on a device.

### M2 — Run one real extension standalone
Take a single Keiyoushi extension APK. Reproduce Suwayomi's load path
(dex→jar conversion + `android.*`/okhttp/jsoup stubs), call `fetchPopularManga()`.
- **Pass:** real manga list (titles + covers) returned from the extension, on the
  device JVM. Confirms the dynamic-load + shim stack works under Zero.

### M3 — Boot full Suwayomi locally
Bundle the Suwayomi server jars; start it from the JNI shim; it opens its HTTP
port on `127.0.0.1`.
- **Pass:** `curl`/URLSession from inside the app hits a Suwayomi API endpoint and
  gets a valid response; an extension installed via its normal API returns sources.

### M4 — Wire Flutter to the local server
Flutter client hits `127.0.0.1:<port>`; run browse → search → open chapter → load
pages end to end. Instrument: **cold-start time**, **first-source-response time**,
**page-load time**, **peak memory**, **added app size (IPA delta)**.
- **Pass:** browsing is usable (network-bound work dominates; interpreter overhead
  on parse is tolerable), memory stays under the iOS jetsam ceiling, size is
  acceptable for a sideloaded app.

### M5 — Go/no-go
Decide on M4 numbers. Acceptable → promote to real integration (Dart
`KotlinExtensionService` behind the existing `getExtensionService` /
`sourceCodeLanguage` switch, Keiyoushi repo installer, lifecycle handling).
Unacceptable → fall back.

---

## Risk register
- **Zero interpreter speed** — ~10–30× slower than JIT. Browsing is network-bound so
  likely fine; heavy HTML parsing (jsoup) is the thing to watch. Measure in M4.
- **App size** — OpenJDK class library + Suwayomi + deps could add 50–150 MB. We
  sideload, so less of a store concern, but still a download.
- **Native-dep libraries** — anything in Suwayomi's tree with JNI/native code must
  have an ios-arm64 build or a pure-Java substitute (H2 is pure-Java = fine; audit
  the rest in M0/M3).
- **iOS lifecycle** — the process (and thus the local server) suspends in
  background. Fine for foreground reading; background downloads won't behave like a
  real server. Handle VM/server pause+resume on app lifecycle.
- **Memory (jetsam)** — a JVM + server in a mobile process is heavy; watch the
  per-app memory limit, especially on older devices.
- **Threading** — JVM threads → pthreads (fine); localhost socket bind (fine).

## Toolchain / where things run (NO Mac owned — CI + sideload workflow)
We don't have a physical Mac. iOS still ships today via the **GitHub macOS
runner** (builds the signed IPA) → Tailscale → **AltStore onto the iPhone**. That
same loop drives this spike. What runs where:
- **OpenJDK Zero for iOS (M0):** GitHub macOS runner (needs the iOS SDK). Cache the
  artifact.
- **Suwayomi shadow-jar:** any box (pure Gradle/JVM) — Linux or the k8s cluster.
- **Android JVM/dex side:** Linux / k8s (no macOS needed).
- **Signed test IPA (M1+):** GitHub macOS runner → Tailscale → AltStore → iPhone.
- **On-device debugging WITHOUT Xcode:** plug the iPhone into the Linux box and use
  **libimobiledevice** — `idevicesyslog` (live device console) and
  `idevicecrashreport` (pull crash logs). This is the key enabler: a JVM boot crash
  on iOS gives almost nothing to go on otherwise. Also build the M1 test app to
  print the JVM's stdout/stderr + any exception straight into its own UI and to a
  log file synced home over Tailscale.
- **This container** does the Dart-side integration *after* M5, and maintains this
  plan.

### The real cost of no Mac
Feasibility is unchanged — the pipeline already produces working iOS builds. The
cost is the **debug loop**: every iOS iteration is a CI round-trip (minutes, not
seconds), and there's no Xcode/lldb to step through a native crash. That makes
**M1 harder to diagnose**, not impossible — lean on libimobiledevice logs + heavy
in-app logging. Budget for slow iteration on M0/M1 specifically.

## Fallback if M1/M5 fails
- **Android:** load Tachiyomi extension APKs natively via `PathClassLoader` (ART
  has JIT; Mihon-style) — much simpler, no bundled server. Kotlin works on Android.
- **iOS:** stays Dart/JS-only for third-party sources; keep porting popular sources
  to Dart (RepoForge/Foxtensions).
- Behavior is identical where both exist; only the plumbing differs.

## Android (deferred until iOS is proven)
Two options, decide after M5:
1. **Bundle the same Suwayomi (dexed for ART)** — uniform Dart bridge across both
   OSes; heavier on Android than it needs to be.
2. **Native APK loading (Mihon-style)** — simplest/lightest on Android, but a
   second extension runtime to maintain. Same user-visible result.
