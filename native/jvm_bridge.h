// Shared desktop (Windows + Linux) bridge to the embedded OpenJDK that hosts the
// Kotlin extension runner (foxtensions.runner.SourceRunner). Mirrors the iOS
// ios/Runner/JvmBridge.m, minus the Zero-VM/DoH workarounds (desktop JVMs have a
// real JIT and real DNS). Compiled into both windows/runner and linux/runner.
#ifndef FOXLATIONS_JVM_BRIDGE_H_
#define FOXLATIONS_JVM_BRIDGE_H_

#include <string>

namespace foxjvm {

// True if the bundled JVM library can be found and loaded. Cheap; boots nothing.
bool IsAvailable();

// Boots the embedded JVM exactly once (thread-safe). Returns true when the VM is
// ready; on failure returns false and sets *err.
bool Warmup(std::string* err);

// Attaches the calling (worker) thread to the VM and calls
// SourceRunner.invoke(request, rootDir), returning its JSON String result. On
// failure returns "" and sets *err. Boots the VM first if needed.
std::string Invoke(const std::string& request, std::string* err);

}  // namespace foxjvm

#endif  // FOXLATIONS_JVM_BRIDGE_H_
