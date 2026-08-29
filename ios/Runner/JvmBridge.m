#import "JvmBridge.h"

#if defined(FOXLATIONS_JVM)

#import <pthread.h>
#include <stdarg.h>
#include <string.h>
#include <signal.h>
#include <jni.h>

// JNI_CreateJavaVM lives in the statically-linked libjvm.a (force_loaded by the build).
extern jint JNI_CreateJavaVM(JavaVM **pvm, void **penv, void *args);

static JavaVM *gJvm = NULL;              // created once; JNI_CreateJavaVM can't run twice
static pthread_mutex_t gJvmLock = PTHREAD_MUTEX_INITIALIZER;

// ── Signal-handler ownership ─────────────────────────────────────────────────
// The JVM installs PROCESS-WIDE SIGSEGV/SIGBUS/… handlers. On the iOS Zero VM,
// os::Posix::ucontext_get_pc is an unimplemented "ShouldNotCall" stub, so the instant
// any such signal reaches the JVM handler — including a BENIGN one iOS/ObjC/JavaScriptCore
// raise on the MAIN thread while returning from background (WebKit ProcessStateMonitor →
// RunningBoard XPC, or willEnterForeground → class_conformsToProtocol) — the JVM aborts
// the whole process (SIGABRT). Zero interprets with explicit checks and doesn't need those
// handlers, so we let the app (Dart / JavaScriptCore) keep owning them.
//
// Restoring only once right after JNI_CreateJavaVM is NOT enough: HotSpot re-installs its
// crash-signal handlers when a worker thread attaches (each JVM call runs on a fresh
// pthread that AttachCurrentThreads), so the first source you open re-arms them and the
// boot-time restore is undone. Instead: snapshot the app's handlers once, and re-assert
// them after EVERY JVM interaction (see jvm_worker) so that between ops — which is when
// background↔foreground transitions happen — the app always owns these signals.
static const int gCrashSigs[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP, SIGPIPE };
enum { kNumCrashSigs = 6 };
static struct sigaction gAppSigActs[kNumCrashSigs];
static bool gAppSigSaved = false;

static void foxSnapshotAppSignals(void) {
    if (gAppSigSaved) return;
    for (int i = 0; i < kNumCrashSigs; i++) sigaction(gCrashSigs[i], NULL, &gAppSigActs[i]);
    gAppSigSaved = true;
}
static void foxRestoreAppSignals(void) {
    if (!gAppSigSaved) return;
    for (int i = 0; i < kNumCrashSigs; i++) sigaction(gCrashSigs[i], &gAppSigActs[i], NULL);
}

static NSString *bundlePath(NSString *rel) {
    return [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:rel];
}

// HotSpot routes its output through this hook; keeps VM messages in the redirected stdout.
static int jvm_vfprintf(FILE *fp, const char *fmt, va_list ap) {
    char buf[8192];
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    fputs(buf, stdout);
    return n;
}

static NSString *documentsDir(void) {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
}

// Boot the VM once, or attach the calling thread to the already-created VM. Must run on a
// large-stack thread. Returns 0 with *outEnv set on success.
static int ensureJvm(JNIEnv **outEnv) {
    pthread_mutex_lock(&gJvmLock);
    if (gJvm) {
        (*gJvm)->AttachCurrentThread(gJvm, (void **)outEnv, NULL);
        pthread_mutex_unlock(&gJvmLock);
        return (*outEnv) ? 0 : -1;
    }

    NSString *doc = documentsDir();
    // Capture VM output/aborts to retrievable, unbuffered files.
    freopen([doc stringByAppendingPathComponent:@"jvm_stderr.txt"].fileSystemRepresentation, "w", stderr);
    freopen([doc stringByAppendingPathComponent:@"jvm_stdout.txt"].fileSystemRepresentation, "w", stdout);
    setvbuf(stderr, NULL, _IONBF, 0);
    setvbuf(stdout, NULL, _IONBF, 0);

    NSString *home    = [NSString stringWithFormat:@"-Djava.home=%@", bundlePath(@"lib")];
    // Boot classpath: our harness/DoH classes + the Kotlin runner + the anime framework +
    // the Suwayomi host, so native FindClass("foxtensions/runner/SourceRunner") resolves and
    // SourceRunner's deps (eu.kanade.*, the eu.kanade.tachiyomi.animesource.* framework,
    // OkHttp, Koin, kotlin-stdlib) live on the SAME (system) classloader.
    NSString *cp      = [NSString stringWithFormat:@"-Djava.class.path=%@:%@:%@:%@",
        bundlePath(@"classes"),
        bundlePath(@"jars/runner.jar"),
        bundlePath(@"jars/animesource.jar"),
        bundlePath(@"jars/suwayomi-server.jar")];
    NSString *errFile = [NSString stringWithFormat:@"-XX:ErrorFile=%@/hs_err_%%p.log", doc];
    // OkHttp's cache uses java.io.tmpdir (defaults to /var/tmp on iOS = outside sandbox);
    // the JDK caches it in a static final, so it must be a -D option, not setProperty.
    NSString *tmpDir  = [doc stringByAppendingPathComponent:@"tmp"];
    [NSFileManager.defaultManager createDirectoryAtPath:tmpDir
        withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tmpOpt  = [NSString stringWithFormat:@"-Djava.io.tmpdir=%@", tmpDir];
    // Where the bundled extension/host jars live, so SourceRunner can resolve jar names.
    NSString *jarsOpt = [NSString stringWithFormat:@"-Dfoxlations.jarsDir=%@", bundlePath(@"jars")];
    // Cloudflare: point Suwayomi's CloudflareInterceptor at the Dart loopback
    // FlareSolverr endpoint (CfFlareSolverrServer, backed by WKWebView). Fixed
    // port must match CfFlareSolverrServer.port. SourceRunner.enableCloudflareSolver
    // reads this to flip flareSolverrEnabled on.
    NSString *cfOpt   = @"-Dfoxlations.flareSolverrUrl=http://127.0.0.1:52700";

    JavaVMOption opts[10];
    memset(opts, 0, sizeof(opts));
    int n = 0;
    opts[n].optionString = (char *)"vfprintf"; opts[n].extraInfo = (void *)jvm_vfprintf; n++;
    opts[n++].optionString = (char *)home.UTF8String;
    opts[n++].optionString = (char *)cp.UTF8String;
    opts[n++].optionString = (char *)tmpOpt.UTF8String;
    opts[n++].optionString = (char *)jarsOpt.UTF8String;
    // iOS Zero port's native DNS returns the wildcard; force IPv4 stack (a DoH resolver
    // registered in classes/ then does the real resolution over a literal IP).
    opts[n++].optionString = (char *)"-Djava.net.preferIPv4Stack=true";
    opts[n++].optionString = (char *)"-Xrs";        // don't fight iOS signal handlers
    opts[n++].optionString = (char *)"-Xshare:off"; // no CDS archive present
    opts[n++].optionString = (char *)errFile.UTF8String;
    opts[n++].optionString = (char *)cfOpt.UTF8String;

    JavaVMInitArgs vmArgs;
    vmArgs.version = JNI_VERSION_1_8;
    vmArgs.nOptions = n;
    vmArgs.options = opts;
    vmArgs.ignoreUnrecognized = JNI_TRUE;

    // Snapshot the app's crash-signal handlers, let the VM install its own during
    // CreateJavaVM, then restore the app's (see the note by gCrashSigs above). The
    // per-op restore in jvm_worker keeps them restored as the VM re-arms them later.
    foxSnapshotAppSignals();

    JavaVM *jvm = NULL; JNIEnv *env = NULL;
    jint rc = JNI_CreateJavaVM(&jvm, (void **)&env, &vmArgs);

    foxRestoreAppSignals();

    if (rc != JNI_OK || env == NULL) {
        pthread_mutex_unlock(&gJvmLock);
        return (int)rc ? (int)rc : -1;
    }
    gJvm = jvm;
    *outEnv = env;
    pthread_mutex_unlock(&gJvmLock);
    return 0;
}

// Runs on a worker thread: boot/attach, then call ExtHarness.probe and return its report.
static NSString *runProbe(void) {
    JNIEnv *env = NULL;
    int rc = ensureJvm(&env);
    if (rc != 0 || env == NULL) {
        return [NSString stringWithFormat:@"JVM boot failed (rc=%d)", rc];
    }

    NSMutableString *msg = [NSMutableString stringWithString:@"JVM OK"];
    jclass sys = (*env)->FindClass(env, "java/lang/System");
    if (sys) {
        jmethodID getProp = (*env)->GetStaticMethodID(env, sys, "getProperty",
            "(Ljava/lang/String;)Ljava/lang/String;");
        jstring key = (*env)->NewStringUTF(env, "java.version");
        jstring ver = (jstring)(*env)->CallStaticObjectMethod(env, sys, getProp, key);
        if (ver) {
            const char *vs = (*env)->GetStringUTFChars(env, ver, NULL);
            [msg appendFormat:@" (java.version=%s)", vs];
            (*env)->ReleaseStringUTFChars(env, ver, vs);
        }
        (*env)->DeleteLocalRef(env, key);
    }

    jclass harness = (*env)->FindClass(env, "ExtHarness");
    if (!harness) {
        (*env)->ExceptionClear(env);
        [msg appendString:@"\nExtHarness not found on classpath"];
        return msg;
    }
    jmethodID probe = (*env)->GetStaticMethodID(env, harness, "probe",
        "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    if (!probe) {
        (*env)->ExceptionClear(env);
        [msg appendString:@"\nExtHarness.probe not found"];
        return msg;
    }
    jstring jp = (*env)->NewStringUTF(env, bundlePath(@"jars/probe.jar").UTF8String);
    jstring je = (*env)->NewStringUTF(env, bundlePath(@"jars/extension.jar").UTF8String);
    jstring js = (*env)->NewStringUTF(env, bundlePath(@"jars/suwayomi-server.jar").UTF8String);
    jstring jw = (*env)->NewStringUTF(env, documentsDir().UTF8String);
    jstring jr = (jstring)(*env)->CallStaticObjectMethod(env, harness, probe, jp, je, js, jw);
    if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionDescribe(env); (*env)->ExceptionClear(env); }
    if (jr) {
        const char *rs = (*env)->GetStringUTFChars(env, jr, NULL);
        [msg appendFormat:@"\n\n%s", rs];
        (*env)->ReleaseStringUTFChars(env, jr, rs);
        (*env)->DeleteLocalRef(env, jr);
    }
    (*env)->DeleteLocalRef(env, jp); (*env)->DeleteLocalRef(env, je);
    (*env)->DeleteLocalRef(env, js); (*env)->DeleteLocalRef(env, jw);
    // Also drop the report in Documents so it's retrievable via the Files app, same as
    // the standalone JvmBoot test harness.
    [msg writeToFile:[documentsDir() stringByAppendingPathComponent:@"jvmboot.txt"]
          atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return msg;
}

// M5.2 JSON RPC: boot/attach then call SourceRunner.invoke(reqJson, doc) -> JSON string.
// The Java string comes back as UTF-16 (GetStringChars) so non-ASCII manga titles survive.
static NSString *runInvoke(NSString *reqJson) {
    JNIEnv *env = NULL;
    int rc = ensureJvm(&env);
    if (rc != 0 || env == NULL) return [NSString stringWithFormat:@"{\"error\":\"JVM boot failed rc=%d\"}", rc];
    jclass runner = (*env)->FindClass(env, "foxtensions/runner/SourceRunner");
    if (!runner) { (*env)->ExceptionClear(env); return @"{\"error\":\"SourceRunner not found\"}"; }
    jmethodID m = (*env)->GetStaticMethodID(env, runner, "invoke",
        "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
    if (!m) { (*env)->ExceptionClear(env); return @"{\"error\":\"SourceRunner.invoke missing\"}"; }
    jstring jreq = (*env)->NewStringUTF(env, reqJson.UTF8String);
    jstring jdoc = (*env)->NewStringUTF(env, documentsDir().UTF8String);
    jstring jr = (jstring)(*env)->CallStaticObjectMethod(env, runner, m, jreq, jdoc);
    NSString *resp = @"{\"error\":\"null response\"}";
    if ((*env)->ExceptionCheck(env)) { (*env)->ExceptionDescribe(env); (*env)->ExceptionClear(env); }
    if (jr) {
        const jchar *ch = (*env)->GetStringChars(env, jr, NULL);
        jsize len = (*env)->GetStringLength(env, jr);
        resp = [NSString stringWithCharacters:(const unichar *)ch length:(NSUInteger)len];
        (*env)->ReleaseStringChars(env, jr, ch);
        (*env)->DeleteLocalRef(env, jr);
    }
    (*env)->DeleteLocalRef(env, jreq);
    (*env)->DeleteLocalRef(env, jdoc);
    return resp;
}

// All JVM work runs on a dedicated 16 MB-stack thread (iOS's 512 KB default is far too
// small for HotSpot); the completion is delivered on the main queue.
static void *jvm_worker(void *arg) {
    void (^work)(void) = (__bridge_transfer void (^)(void))arg;
    @autoreleasepool { work(); }
    // Attaching this worker (and the JVM work it just ran) re-arms the VM's process-wide
    // crash-signal handlers; hand them back to the app so a background↔foreground signal on
    // the main thread doesn't reach the JVM's aborting handler. See the note by gCrashSigs.
    foxRestoreAppSignals();
    return NULL;
}
static void spawnJvmThread(void (^work)(void)) {
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 16 * 1024 * 1024);
    pthread_t t;
    int rc = pthread_create(&t, &attr, jvm_worker, (__bridge_retained void *)[work copy]);
    pthread_attr_destroy(&attr);
    if (rc == 0) pthread_detach(t); else work();
}

void FoxJvmProbeAsync(void (^completion)(NSString *report)) {
    spawnJvmThread(^{
        NSString *report = runProbe();
        dispatch_async(dispatch_get_main_queue(), ^{ completion(report ?: @"(no report)"); });
    });
}

void FoxJvmInvokeAsync(NSString *reqJson, void (^completion)(NSString *responseJson)) {
    NSString *req = [reqJson copy];
    spawnJvmThread(^{
        NSString *resp = runInvoke(req);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(resp ?: @"{\"error\":\"null\"}"); });
    });
}

#else  // !FOXLATIONS_JVM — normal production build: inert stub, no JVM linked.

void FoxJvmProbeAsync(void (^completion)(NSString *report)) {
    completion(@"JVM integration not built (FOXLATIONS_JVM undefined)");
}

void FoxJvmInvokeAsync(NSString *reqJson, void (^completion)(NSString *responseJson)) {
    completion(@"{\"error\":\"JVM integration not built (FOXLATIONS_JVM undefined)\"}");
}

#endif
