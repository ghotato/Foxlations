// M1 make-or-break: boot the statically-linked OpenJDK Zero VM inside a bare
// iOS app and prove it ran, by reading java.version back through JNI.
//
// Design notes / the parts most likely to need iteration:
//  - JNI_CreateJavaVM is a symbol inside the statically-linked libjvm.a; the
//    workflow links the JDK static libs with -force_load so it (and the
//    JNI_OnLoad_<lib> registration + native-method symbols) survive dead-strip.
//  - The VM runs on a dedicated pthread with a LARGE stack (iOS non-main
//    threads default to 512 KB, far too small for the JVM). Never create the VM
//    on the UI main thread.
//  - java.home points at the bundled EXPLODED image (java-home/ with modules/),
//    which HotSpot boots from directly.
//  - Result is surfaced three ways so we can read it no matter what: an on-screen
//    label, NSLog (visible via `idevicesyslog` over USB from Linux), and a file
//    in Documents.

#import <UIKit/UIKit.h>
#import <pthread.h>
#include <stdarg.h>
#include <string.h>
#include <jni.h>

// Provided by the statically-linked libjvm.a.
extern jint JNI_CreateJavaVM(JavaVM **pvm, void **penv, void *args);

static NSString *gResult = nil;  // strong global; written on jvm thread, read on main

static NSString *bundlePath(NSString *rel) {
    return [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:rel];
}

static void publish(NSString *s) {
    gResult = s;
    NSLog(@"[JVMBOOT] %@", s);
    NSString *doc = [NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    [s writeToFile:[doc stringByAppendingPathComponent:@"jvmboot.txt"]
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static jstring sysProp(JNIEnv *env, jclass sys, jmethodID getProp, const char *key) {
    jstring k = (*env)->NewStringUTF(env, key);
    jstring v = (jstring)(*env)->CallStaticObjectMethod(env, sys, getProp, k);
    (*env)->DeleteLocalRef(env, k);
    return v;
}

// HotSpot routes its output through this hook when registered, so we capture
// every VM message — even ones that never reach the redirected stdout (which is
// why rc=-6 printed nothing). Writes into jvm_stdout.txt (stdout is redirected).
static int jvm_vfprintf(FILE *fp, const char *fmt, va_list ap) {
    char buf[8192];
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    fputs(buf, stdout);
    return n;
}

static void *jvm_thread(void *arg) {
    @autoreleasepool {
        NSString *doc = [NSSearchPathForDirectoriesInDomains(
            NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        // The VM aborts (exit/abort) on an init error instead of returning, so
        // its reason would otherwise be lost. Redirect stdout/stderr to
        // retrievable files, UNBUFFERED so the message survives an abort, and
        // point the fatal-error report at a writable path.
        freopen([doc stringByAppendingPathComponent:@"jvm_stderr.txt"].fileSystemRepresentation, "w", stderr);
        freopen([doc stringByAppendingPathComponent:@"jvm_stdout.txt"].fileSystemRepresentation, "w", stdout);
        setvbuf(stderr, NULL, _IONBF, 0);
        setvbuf(stdout, NULL, _IONBF, 0);

        // On iOS a statically-linked libjvm forces java.home = <App.app>/lib
        // (it ignores -Djava.home), so the runtime image lives there and we
        // point the property at the same place for consistency.
        NSString *jhPath = bundlePath(@"lib");
        NSString *home = [NSString stringWithFormat:@"-Djava.home=%@", jhPath];
        NSString *cp   = [NSString stringWithFormat:@"-Djava.class.path=%@", bundlePath(@"classes")];
        NSString *errFile = [NSString stringWithFormat:@"-XX:ErrorFile=%@/hs_err_%%p.log", doc];

        // OkHttp's network cache calls Files.createTempDirectory, which uses
        // java.io.tmpdir — on iOS that defaults to /var/tmp (outside the sandbox ->
        // "Operation not permitted"). The JDK caches java.io.tmpdir in a static final
        // at class-load, so setting it at runtime is too late; pass it as a -D option
        // pointing at a writable Documents/tmp dir (created here) before the VM boots.
        NSString *tmpDir = [doc stringByAppendingPathComponent:@"tmp"];
        [NSFileManager.defaultManager createDirectoryAtPath:tmpDir
            withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *tmpOpt = [NSString stringWithFormat:@"-Djava.io.tmpdir=%@", tmpDir];

        // Diagnostics for "Failed setting boot class path": confirm the class
        // library really is in the bundle at the path we hand the VM, and let
        // -Xlog:class+path show which path the VM itself resolves (it may ignore
        // -Djava.home for a statically-linked libjvm and derive it from the
        // executable location instead).
        NSFileManager *fm = NSFileManager.defaultManager;
        fprintf(stdout, "[diag] bundlePath=%s\n", NSBundle.mainBundle.bundlePath.UTF8String);
        fprintf(stdout, "[diag] java.home=%s exists=%d\n", jhPath.UTF8String, [fm fileExistsAtPath:jhPath]);
        fprintf(stdout, "[diag] java.home/modules exists=%d\n", [fm fileExistsAtPath:[jhPath stringByAppendingPathComponent:@"modules"]]);
        fprintf(stdout, "[diag] java.home/modules/java.base exists=%d\n", [fm fileExistsAtPath:[jhPath stringByAppendingPathComponent:@"modules/java.base"]]);
        fprintf(stdout, "[diag] java.home/lib/modules exists=%d\n", [fm fileExistsAtPath:[jhPath stringByAppendingPathComponent:@"lib/modules"]]);

        // vfprintf hook captures every VM message (rc=-6 printed nothing to the
        // redirected stdout). memset zeroes extraInfo for the plain options.
        JavaVMOption opts[8];
        memset(opts, 0, sizeof(opts));
        int n = 0;
        // Register the vfprintf hook FIRST so it captures errors from parsing the
        // options that follow (rc=-6 came from an option after it, so the hook
        // wasn't installed yet last time).
        opts[n].optionString = (char *)"vfprintf";
        opts[n].extraInfo = (void *)jvm_vfprintf;
        n++;
        opts[n++].optionString = (char *)home.UTF8String;
        opts[n++].optionString = (char *)cp.UTF8String;
        opts[n++].optionString = (char *)tmpOpt.UTF8String;   // writable java.io.tmpdir
        // DNS resolved api.mangadex.org to the IPv6 wildcard :: — the iOS Zero port's
        // IPv6 resolver path is misbehaving. Force the IPv4 stack so the JVM uses AF_INET
        // sockets + IPv4 DNS. (If this doesn't fix it, the net diagnostic will say why.)
        opts[n++].optionString = (char *)"-Djava.net.preferIPv4Stack=true";
        opts[n++].optionString = (char *)"-Xrs";        // don't install signal handlers that fight iOS
        opts[n++].optionString = (char *)"-Xshare:off"; // no CDS archive present
        opts[n++].optionString = (char *)errFile.UTF8String;

        JavaVMInitArgs vmArgs;
        vmArgs.version = JNI_VERSION_1_8;   // JNI is backward-compatible; accepted by JDK 28
        vmArgs.nOptions = n;
        vmArgs.options = opts;
        vmArgs.ignoreUnrecognized = JNI_TRUE;

        JavaVM *jvm = NULL; JNIEnv *env = NULL;
        jint rc = JNI_CreateJavaVM(&jvm, (void **)&env, &vmArgs);
        if (rc != JNI_OK || env == NULL) {
            publish([NSString stringWithFormat:@"FAIL: JNI_CreateJavaVM rc=%d", (int)rc]);
            return NULL;
        }

        jclass sys = (*env)->FindClass(env, "java/lang/System");
        if (!sys) { publish(@"FAIL: FindClass(java/lang/System)"); return NULL; }
        jmethodID getProp = (*env)->GetStaticMethodID(
            env, sys, "getProperty", "(Ljava/lang/String;)Ljava/lang/String;");

        jstring ver = sysProp(env, sys, getProp, "java.version");
        jstring vm  = sysProp(env, sys, getProp, "java.vm.name");
        const char *vs = ver ? (*env)->GetStringUTFChars(env, ver, NULL) : "?";
        const char *vm2 = vm ? (*env)->GetStringUTFChars(env, vm, NULL) : "?";
        NSMutableString *msg =
            [NSMutableString stringWithFormat:@"JVM OK\n%s\njava.version=%s", vm2, vs];

        // M2: run the Java harness (ExtHarness.probe) to prove dynamic class
        // loading — URLClassLoader on a runtime jar + inspecting a real Keiyoushi
        // extension jar. Doing the heavy lifting in Java keeps the JNI glue tiny:
        // one static call in, one String report out.
        jclass harness = (*env)->FindClass(env, "ExtHarness");
        if (harness) {
            jmethodID probe = (*env)->GetStaticMethodID(
                env, harness, "probe",
                "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;");
            if (probe) {
                jstring jp = (*env)->NewStringUTF(env, bundlePath(@"jars/probe.jar").UTF8String);
                jstring je = (*env)->NewStringUTF(env, bundlePath(@"jars/extension.jar").UTF8String);
                jstring js = (*env)->NewStringUTF(env, bundlePath(@"jars/suwayomi-server.jar").UTF8String);
                jstring jw = (*env)->NewStringUTF(env, doc.UTF8String);   // writable Documents dir
                jstring jr = (jstring)(*env)->CallStaticObjectMethod(env, harness, probe, jp, je, js, jw);
                if ((*env)->ExceptionCheck(env)) {
                    (*env)->ExceptionDescribe(env);
                    (*env)->ExceptionClear(env);
                }
                if (jr) {
                    const char *rs = (*env)->GetStringUTFChars(env, jr, NULL);
                    [msg appendFormat:@"\n\n%s", rs];
                    (*env)->ReleaseStringUTFChars(env, jr, rs);
                    (*env)->DeleteLocalRef(env, jr);
                }
                (*env)->DeleteLocalRef(env, jp);
                (*env)->DeleteLocalRef(env, je);
                (*env)->DeleteLocalRef(env, js);
                (*env)->DeleteLocalRef(env, jw);
            }
        } else {
            (*env)->ExceptionClear(env);
        }
        publish(msg);
        return NULL;
    }
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.blackColor;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(vc.view.bounds, 16, 16)];
    label.numberOfLines = 0;
    label.font = [UIFont monospacedSystemFontOfSize:16 weight:UIFontWeightSemibold];
    label.textColor = UIColor.greenColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.text = @"Booting Zero VM…";
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:label];
    self.window.rootViewController = vc;
    [self.window makeKeyAndVisible];

    // Big stack — the JVM's initial thread needs far more than iOS's 512 KB default.
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 16 * 1024 * 1024);
    pthread_t t;
    pthread_create(&t, &attr, jvm_thread, NULL);
    pthread_attr_destroy(&attr);

    [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:YES block:^(NSTimer *timer) {
        if (gResult) { label.text = gResult; [timer invalidate]; }
    }];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
