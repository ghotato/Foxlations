// MSVC flags getenv() as "unsafe" (C4996) and the Windows runner builds with /WX
// (warnings-as-errors); we use getenv portably, so silence it. No-op elsewhere.
#define _CRT_SECURE_NO_WARNINGS 1

// Shared desktop JVM bridge — see jvm_bridge.h. Boots a bundled OpenJDK via the
// JNI Invocation API and calls foxtensions.runner.SourceRunner.invoke.
//
// Layout at runtime (relative to the executable):
//   <exeDir>/jre/                     bundled runtime (jvm.dll / libjvm.so inside)
//   <exeDir>/jars/{runner,animesource,suwayomi-server}.jar
// Writable data (Suwayomi rootDir, tmp, memo cache) lives in a per-user dir.
#include "jvm_bridge.h"

#include <jni.h>

#include <mutex>
#include <string>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#include <direct.h>
#else
#include <dlfcn.h>
#include <limits.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <cstdlib>
#endif

namespace {

typedef jint(JNICALL* CreateJavaVM_t)(JavaVM**, void**, void*);

std::mutex g_mutex;
JavaVM* g_vm = nullptr;  // created exactly once
bool g_probed = false;
bool g_probe_ok = false;

#if defined(_WIN32)
constexpr char kPathSep = '\\';
constexpr char kClassPathSep = ';';
#else
constexpr char kPathSep = '/';
constexpr char kClassPathSep = ':';
#endif

std::string Join(const std::string& a, const std::string& b) {
  return a + kPathSep + b;
}

// Absolute directory of the running executable.
std::string ExeDir() {
#if defined(_WIN32)
  wchar_t buf[MAX_PATH];
  DWORD n = GetModuleFileNameW(nullptr, buf, MAX_PATH);
  std::wstring w(buf, n);
  size_t slash = w.find_last_of(L'\\');
  std::wstring dirw = (slash == std::wstring::npos) ? w : w.substr(0, slash);
  int len = WideCharToMultiByte(CP_UTF8, 0, dirw.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string dir(len > 0 ? len - 1 : 0, '\0');
  if (len > 0)
    WideCharToMultiByte(CP_UTF8, 0, dirw.c_str(), -1, dir.data(), len, nullptr, nullptr);
  return dir;
#else
  char buf[PATH_MAX];
  ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (n <= 0) return ".";
  buf[n] = '\0';
  std::string p(buf);
  size_t slash = p.find_last_of('/');
  return (slash == std::string::npos) ? std::string(".") : p.substr(0, slash);
#endif
}

std::string JreDir() { return Join(ExeDir(), "jre"); }
std::string JarsDir() { return Join(ExeDir(), "jars"); }

std::string JvmLibPath() {
#if defined(_WIN32)
  return JreDir() + "\\bin\\server\\jvm.dll";
#else
  return JreDir() + "/lib/server/libjvm.so";
#endif
}

// Per-user writable directory: Suwayomi rootDir, tmp, foxlations_memo.json.
std::string DataDir() {
#if defined(_WIN32)
  const char* base = getenv("LOCALAPPDATA");
  std::string root = base && *base ? std::string(base) : ExeDir();
  return Join(root, "Foxlations");
#else
  const char* xdg = getenv("XDG_DATA_HOME");
  std::string root;
  if (xdg && *xdg) {
    root = xdg;
  } else {
    const char* home = getenv("HOME");
    root = std::string(home && *home ? home : ".") + "/.local/share";
  }
  return root + "/foxlations";
#endif
}

void MakeDirs(const std::string& path) {
  std::string acc;
  for (size_t i = 0; i < path.size(); ++i) {
    acc += path[i];
    const bool at_sep = (path[i] == kPathSep);
    const bool at_end = (i + 1 == path.size());
    if (at_sep || at_end) {
      if (acc.empty() || acc == std::string(1, kPathSep)) continue;
#if defined(_WIN32)
      _mkdir(acc.c_str());
#else
      mkdir(acc.c_str(), 0755);
#endif
    }
  }
}

CreateJavaVM_t LoadCreateJavaVM() {
  const std::string lib = JvmLibPath();
#if defined(_WIN32)
  int wlen = MultiByteToWideChar(CP_UTF8, 0, lib.c_str(), -1, nullptr, 0);
  std::wstring wlib(wlen > 0 ? wlen - 1 : 0, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, lib.c_str(), -1, wlib.data(), wlen);
  HMODULE h = LoadLibraryW(wlib.c_str());
  if (!h) return nullptr;
  return reinterpret_cast<CreateJavaVM_t>(
      reinterpret_cast<void*>(GetProcAddress(h, "JNI_CreateJavaVM")));
#else
  void* h = dlopen(lib.c_str(), RTLD_NOW | RTLD_GLOBAL);
  if (!h) return nullptr;
  return reinterpret_cast<CreateJavaVM_t>(dlsym(h, "JNI_CreateJavaVM"));
#endif
}

// Java strings come back as UTF-16; convert to real UTF-8 so non-ASCII manga
// titles survive (GetStringUTFChars would emit modified-UTF-8).
std::string Utf16ToUtf8(const jchar* u, jsize len) {
  std::string out;
  out.reserve(static_cast<size_t>(len) + 8);
  for (jsize i = 0; i < len; ++i) {
    unsigned int cp = u[i];
    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < len) {
      unsigned int lo = u[i + 1];
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cp = 0x10000u + ((cp - 0xD800u) << 10) + (lo - 0xDC00u);
        ++i;
      }
    }
    if (cp < 0x80) {
      out += static_cast<char>(cp);
    } else if (cp < 0x800) {
      out += static_cast<char>(0xC0 | (cp >> 6));
      out += static_cast<char>(0x80 | (cp & 0x3F));
    } else if (cp < 0x10000) {
      out += static_cast<char>(0xE0 | (cp >> 12));
      out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
      out += static_cast<char>(0x80 | (cp & 0x3F));
    } else {
      out += static_cast<char>(0xF0 | (cp >> 18));
      out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
      out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
      out += static_cast<char>(0x80 | (cp & 0x3F));
    }
  }
  return out;
}

// Assumes g_mutex is held.
bool WarmupLocked(std::string* err) {
  if (g_vm) return true;

  CreateJavaVM_t create = LoadCreateJavaVM();
  if (!create) {
    if (err) *err = "JVM library not found at " + JvmLibPath();
    return false;
  }

  const std::string jars = JarsDir();
  const std::string data = DataDir();
  const std::string tmp = Join(data, "tmp");
  MakeDirs(tmp);

  std::string cp = "-Djava.class.path=" + Join(jars, "runner.jar") + kClassPathSep +
                   Join(jars, "animesource.jar") + kClassPathSep +
                   Join(jars, "suwayomi-server.jar");
  std::string jarsOpt = "-Dfoxlations.jarsDir=" + jars;
  std::string tmpOpt = "-Djava.io.tmpdir=" + tmp;
  // Cloudflare loopback FlareSolverr (Dart-side WebView), same fixed port as iOS.
  std::string cfOpt = "-Dfoxlations.flareSolverrUrl=http://127.0.0.1:52700";

  std::vector<std::string> opt_strings = {cp, jarsOpt, tmpOpt, cfOpt};
  std::vector<JavaVMOption> opts;
  for (auto& s : opt_strings) {
    JavaVMOption o;
    o.optionString = const_cast<char*>(s.c_str());
    o.extraInfo = nullptr;
    opts.push_back(o);
  }

  JavaVMInitArgs args;
  args.version = JNI_VERSION_1_8;
  args.nOptions = static_cast<jint>(opts.size());
  args.options = opts.data();
  args.ignoreUnrecognized = JNI_TRUE;

  JNIEnv* env = nullptr;
  jint rc = create(&g_vm, reinterpret_cast<void**>(&env), &args);
  if (rc != JNI_OK || env == nullptr) {
    g_vm = nullptr;
    if (err) *err = "JNI_CreateJavaVM failed (rc=" + std::to_string(rc) + ")";
    return false;
  }
  return true;
}

}  // namespace

namespace foxjvm {

bool IsAvailable() {
  std::lock_guard<std::mutex> lk(g_mutex);
  if (g_probed) return g_probe_ok;
  g_probed = true;
  g_probe_ok = (LoadCreateJavaVM() != nullptr);
  return g_probe_ok;
}

bool Warmup(std::string* err) {
  std::lock_guard<std::mutex> lk(g_mutex);
  return WarmupLocked(err);
}

std::string Invoke(const std::string& request, std::string* err) {
  JavaVM* vm = nullptr;
  {
    std::lock_guard<std::mutex> lk(g_mutex);
    if (!g_vm) {
      std::string e;
      if (!WarmupLocked(&e)) {
        if (err) *err = e;
        return "";
      }
    }
    vm = g_vm;
  }

  JNIEnv* env = nullptr;
  if (vm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr) != JNI_OK ||
      env == nullptr) {
    if (err) *err = "AttachCurrentThread failed";
    return "";
  }

  std::string result;
  bool failed = false;
  std::string fail_msg;

  jclass cls = env->FindClass("foxtensions/runner/SourceRunner");
  if (env->ExceptionCheck()) { env->ExceptionClear(); }
  if (cls) {
    jmethodID mid = env->GetStaticMethodID(
        cls, "invoke",
        "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    if (mid) {
      jstring jreq = env->NewStringUTF(request.c_str());
      jstring jroot = env->NewStringUTF(DataDir().c_str());
      jobject jres = env->CallStaticObjectMethod(cls, mid, jreq, jroot);
      if (env->ExceptionCheck()) {
        env->ExceptionClear();
        failed = true;
        fail_msg = "java exception during invoke";
      } else if (jres) {
        jstring jstr = static_cast<jstring>(jres);
        const jchar* chars = env->GetStringChars(jstr, nullptr);
        jsize len = env->GetStringLength(jstr);
        if (chars) {
          result = Utf16ToUtf8(chars, len);
          env->ReleaseStringChars(jstr, chars);
        }
      }
      if (jreq) env->DeleteLocalRef(jreq);
      if (jroot) env->DeleteLocalRef(jroot);
      if (jres) env->DeleteLocalRef(jres);
    } else {
      failed = true;
      fail_msg = "SourceRunner.invoke not found";
    }
    env->DeleteLocalRef(cls);
  } else {
    failed = true;
    fail_msg = "SourceRunner class not found on classpath";
  }

  vm->DetachCurrentThread();
  if (failed) {
    if (err) *err = fail_msg;
    return "";
  }
  return result;
}

}  // namespace foxjvm
