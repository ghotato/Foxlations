// iOS-Zero stubs for the Apple-arm64 JIT / W^X (write-xor-execute) symbols that
// HotSpot's SHARED code references but the Zero os_cpu layer never defines. On
// Apple/arm64 these live only in os_cpu/bsd_aarch64/os_bsd_aarch64.cpp, which a
// --with-jvm-variants=zero build does not compile (it builds os_cpu/bsd_zero
// instead, and that file defines only current_thread_enable_wx — not these three).
// Yet `-DAARCH64` is still passed to every TU, so MACOS_AARCH64 is defined and the
// shared code (memory/heap.cpp CodeHeap::reserve, interfaceSupport.inline.hpp) DOES
// reference them. That leaves them undefined at link, so we supply them here.
//
// This is the same stub the standalone M1 spike used (docs/kotlin-extensions/m1/
// ios_wx_stubs.cpp), brought into the Runner target so linking libjvm into the real
// app resolves these symbols. Gated on FOXLATIONS_JVM so it's inert if it ever ends
// up in a non-JVM build.
//
// ── Why _jit_exec_enabled MUST be __thread ───────────────────────────────────
// os.hpp declares `static THREAD_LOCAL bool _jit_exec_enabled;` (THREAD_LOCAL is
// __thread). On Darwin/arm64 a __thread read is lowered to a call through a TLV
// descriptor thunk; defining it as a PLAIN global makes word 0 the zero byte, so the
// emitted `blr` branches to pc=0 (Instruction Abort inside CodeHeap::reserve). The
// `__thread` keyword makes the linker emit a real TLV descriptor.
#if defined(FOXLATIONS_JVM)

class os {
 public:
  static __thread bool _jit_exec_enabled;      // MUST be __thread (see note above)
  static void thread_wx_enable_write_impl();
};

// No JIT on iOS and Zero never executes generated compiled code, so W^X flipping is
// a genuine no-op. _jit_exec_enabled is never armed true on a Zero iOS build, so the
// impl is never reached. Do NOT call Thread::current()->wx_enable_write() — it lives
// in os_bsd_aarch64.cpp, which the Zero variant does not build.
__thread bool os::_jit_exec_enabled = false;
void os::thread_wx_enable_write_impl() {}

// Global WXMode default (unmangled C++ global -> symbol _DefaultWXWriteMode).
// WXWrite == 0 means "never arm write-protect", correct for a no-JIT interpreter.
int DefaultWXWriteMode = 0;

#endif
