# M0 — Build the iOS JVM (grounded recipe)

**Key finding that changes M0's risk:** we do **not** port OpenJDK ourselves.
There is an **official OpenJDK "Mobile" project** that already builds a **static
`libjvm.a` for iOS using the Zero interpreter** — precisely because iOS forbids
JIT / W+X memory. M0 becomes "drive the official build on our macOS runner and
cache the artifact," not "write an iOS HotSpot port."

- Project: OpenJDK Mobile — https://openjdk.org/projects/mobile/ios.html and
  the `openjdk/mobile` repo. Actively worked (mobile-dev list, 2025).
- Existence proofs a full JVM runs on sideloaded iOS:
  - **PojavLauncher** — runs desktop Java (Minecraft) on iOS.
  - **thebaselab** — got OpenJDK 8 running on iOS.
  - **miniJVM** (digitalgust/miniJVM) — minimal JVM, iOS/Android, JIT-disable
    option (a lighter fallback engine if full OpenJDK proves too heavy).

Everything below marked **[verified]** is quoted from the official iOS build page.
Anything marked **[standard-practice / to-verify]** is the normal way it's done but
not yet confirmed against this port on our setup — treat those as the spike's real
unknowns.

---

## Prerequisites [verified]
- **Boot JDK for macOS.** The official page says JDK 24, but the live repo has
  advanced to **JDK 28-dev**, so configure actually demands a boot JDK of
  **26/27/28** (confirmed by a real run 2026-08-07). We use **26** (highest GA);
  bump as the repo moves. The repo tracking mainline means this will drift —
  consider pinning the openjdk/mobile checkout to a ref for reproducibility.
- A **"mobile support zip"** containing prebuilt **libffi** and **cups** for iOS
  (the project supplies these; they're deps the JDK needs cross-built for iOS).
- **autoconf** (`brew install autoconf`).
- Xcode with the iOS SDK (the macOS runner has this).

## Configure [verified — quote verbatim]
```bash
sh configure \
  --disable-warnings-as-errors \
  --openjdk-target=aarch64-macos-ios \
  --with-libffi-include=<support-dir>/libffi/include \
  --with-libffi-lib=<support-dir>/libffi/libs \
  --with-cups-include=<support-dir>/cups-2.3.6 \
  --with-sysroot=/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk
```
Optional:
- `--with-boot-jdk=<path>` if the boot JDK isn't auto-found.
- `--with-jvm-variants=server` **for the simulator only** (the simulator runs on
  the Mac, where JIT is allowed, so it iterates faster). **Device build stays
  Zero** — the simulator does NOT prove the no-JIT path, so M1's real-device test
  must use the Zero build. (Zero is the default for iOS.)

## Build [verified]
```bash
make CONF=ios-aarch64-zero-release static-libs-image
```

## Artifact [verified]
```
build/ios-aarch64-zero-release/images/static-libs/lib/zero/libjvm.a
```

---

## What `static-libs-image` gives you vs. what you still need [standard-practice / to-verify]
`static-libs-image` produces the **native static libraries** (`libjvm.a`, plus the
JDK's native libs — `libjava`, `libnio`, `libnet`, `libzip`, etc. as static `.a`).
To actually run Java you ALSO need, bundled in the app:
1. **The Java class library** — the `lib/modules` (jimage) or an equivalent runtime
   image. A static `libjvm.a` still loads classes from a module image at runtime.
2. **All required native static libs linked into the app binary**, not `dlopen`ed —
   iOS restricts loading arbitrary dylibs, so a **statically linked** JVM is the
   safe path.

**Static-linking JNI wrinkle:** with a statically linked JDK, native methods aren't
found by `dlopen`; each static native lib must be registered via its
`JNI_OnLoad_<libname>` entry point (the "static JNI" mechanism). Expect to wire
these up in the launcher shim. **[to-verify against this port]**

## Module trimming [standard-practice / to-verify]
Suwayomi + a Tachiyomi extension need a real chunk of `java.base` plus things like
`java.net.http`, `java.sql` (H2), `java.xml`, `jdk.crypto*`. Trim with `jlink` to a
minimal image to cut size:
```bash
jlink --add-modules java.base,java.net.http,java.sql,java.xml,jdk.crypto.ec,jdk.unsupported \
      --strip-debug --no-header-files --no-man-pages --compress=2 \
      --output ios-runtime
```
The exact module set is unknown until M2/M3 surface `NoClassDefFoundError`s — start
minimal, add modules as extensions demand them. `jdk.unsupported` (sun.misc.Unsafe)
is very likely needed by the Kotlin/coroutines/OkHttp stack.

---

## GitHub Actions skeleton (macOS runner, cache the heavy build)
This is the shape, not a finished workflow — the `<support-dir>` (libffi/cups zip)
sourcing and the module image packaging are the parts to finalize during the spike.

```yaml
name: build-ios-jvm
on: workflow_dispatch

jobs:
  build-libjvm:
    runs-on: macos-14          # arm64 runner, current Xcode
    steps:
      - name: Cache the built iOS libjvm + runtime image
        id: cache
        uses: actions/cache@v4
        with:
          path: artifacts/ios-jvm
          # bump the version suffix to force a rebuild
          key: ios-jvm-zero-${{ hashFiles('.jvm-build-rev') }}-v1

      - name: Check out openjdk/mobile
        if: steps.cache.outputs.cache-hit != 'true'
        uses: actions/checkout@v4
        with: { repository: openjdk/mobile, path: mobile }

      - name: Boot JDK 24 + autoconf
        if: steps.cache.outputs.cache-hit != 'true'
        run: |
          brew install autoconf
          # set up JDK 24 (setup-java or a downloaded macOS JDK 24)

      - name: Fetch iOS support libs (libffi + cups zip)
        if: steps.cache.outputs.cache-hit != 'true'
        run: echo "TODO: obtain/build the mobile support zip -> support-dir/"

      - name: Configure (Zero, iOS device)
        if: steps.cache.outputs.cache-hit != 'true'
        working-directory: mobile
        run: |
          sh configure --disable-warnings-as-errors \
            --openjdk-target=aarch64-macos-ios \
            --with-libffi-include=$SUPPORT/libffi/include \
            --with-libffi-lib=$SUPPORT/libffi/libs \
            --with-cups-include=$SUPPORT/cups-2.3.6 \
            --with-sysroot=$(xcrun --sdk iphoneos --show-sdk-path)

      - name: Build static libs
        if: steps.cache.outputs.cache-hit != 'true'
        working-directory: mobile
        run: make CONF=ios-aarch64-zero-release static-libs-image

      - name: Stage libjvm.a + runtime image
        if: steps.cache.outputs.cache-hit != 'true'
        run: |
          mkdir -p artifacts/ios-jvm
          cp mobile/build/ios-aarch64-zero-release/images/static-libs/lib/zero/libjvm.a artifacts/ios-jvm/
          # TODO: also stage the jlink'd runtime image + other static .a libs

      - uses: actions/upload-artifact@v4
        with: { name: ios-jvm, path: artifacts/ios-jvm }
```

Notes:
- Runner minutes: a full JDK build is long but fits GitHub's per-job limit; the
  `actions/cache` step means it runs once until `.jvm-build-rev` changes.
- The libffi/cups "support zip" is a real dependency to pin down — either grab the
  project's prebuilt one or add a step that cross-builds them. This is the first
  thing to nail in a `workflow_dispatch` trial run.

## M0 exit criteria
- `libjvm.a` (Zero, ios-arm64) produced and cached.
- A throwaway iOS test target **links** against it with no missing symbols
  (proves the static libs are coherent) — the *running* proof is M1.

## Open questions to resolve during M0 (the honest unknowns)
1. Sourcing the libffi/cups iOS support zip (prebuilt vs. build it).
2. Packaging the class-library/module image for a statically linked, sandboxed app
   (the "Copy Bundle Resources breaks library paths" gotcha the community flags).
3. Which JDK version openjdk/mobile currently targets (page says boot JDK 24 — the
   built JDK version may differ; confirm before pinning).
4. `JNI_OnLoad_<lib>` static registration set for the native libs we link.

## Sources
- https://openjdk.org/projects/mobile/ios.html (build commands, Zero, artifact path)
- https://openjdk.org/projects/mobile/ (project)
- https://openjdk.org/projects/zero/ (Zero interpreter)
- https://github.com/openjdk/mobile
- https://github.com/digitalgust/miniJVM (lighter fallback JVM)
