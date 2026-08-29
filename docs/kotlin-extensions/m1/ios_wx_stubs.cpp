// iOS-Zero stubs for the Apple-arm64 JIT / W^X (write-xor-execute) symbols that
// HotSpot's SHARED code references but the Zero os_cpu layer never defines. On
// Apple/arm64 these live only in os_cpu/bsd_aarch64/os_bsd_aarch64.cpp, which a
// --with-jvm-variants=zero build does not compile (it builds os_cpu/bsd_zero
// instead, and that file defines only current_thread_enable_wx — not these three).
// Yet `-DAARCH64` is still passed to every TU, so MACOS_AARCH64 is defined and the
// shared code (memory/heap.cpp CodeHeap::reserve, interfaceSupport.inline.hpp) DOES
// reference them. That leaves them undefined at link, so we supply them here.
//
// ── Why the first attempt crashed at pc=0 ────────────────────────────────────
// os.hpp declares `static THREAD_LOCAL bool _jit_exec_enabled;`, and THREAD_LOCAL
// is `__thread` (globalDefinitions_gcc.hpp). On Darwin/arm64 a read of a __thread
// variable is lowered to a call through a TLV descriptor thunk (the descriptor's
// word 0 is a dyld resolver function pointer). If we define the symbol as a PLAIN
// global bool, word 0 is the zero-initialised byte 0x00, so the emitted `blr`
// branches to address 0 — an Instruction Abort at pc=0 inside CodeHeap::reserve
// with x0 = &os::_jit_exec_enabled. It faults *reading* the variable, before its
// value is ever tested (so initialising it to false cannot help). The one keyword
// that matters is therefore `__thread`: it must match the header's storage class
// so the linker emits a real TLV descriptor.
//
// `os` in HotSpot is a class of static members; we redeclare ONLY the two members
// we must define, enough to emit the exact mangled symbols the linker wants
// (__ZN2os17_jit_exec_enabledE and __ZN2os27thread_wx_enable_write_implEv). We
// never instantiate os, so this minimal declaration can't clash with anything.
class os {
 public:
  static __thread bool _jit_exec_enabled;      // MUST be __thread (see note above)
  static void thread_wx_enable_write_impl();
};

// No JIT on iOS and Zero never executes generated compiled code, so W^X flipping
// is a genuine no-op. _jit_exec_enabled is never armed true on a Zero iOS build
// (the aarch64 current_thread_enable_wx that would set it isn't compiled, and the
// pthread_jit_write_protect_np path is #ifndef __IOS__), so the impl is never even
// reached at runtime. Do NOT call Thread::current()->wx_enable_write() here — that
// lives in os_bsd_aarch64.cpp, which the Zero variant does not build.
__thread bool os::_jit_exec_enabled = false;
void os::thread_wx_enable_write_impl() {}

// Global WXMode default (unmangled C++ global → symbol _DefaultWXWriteMode).
// The real type is the enum WXMode whose first enumerator WXWrite == 0; leaving
// this 0 means "never arm write-protect", which is exactly right for a no-JIT
// interpreter. Declared int here only to avoid pulling in the MACOS_AARCH64-gated
// enum; same size (4 bytes), same symbol, same value.
int DefaultWXWriteMode = 0;
