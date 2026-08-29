#ifndef FOXLATIONS_JVMBRIDGE_H
#define FOXLATIONS_JVMBRIDGE_H

#import <Foundation/Foundation.h>

// M5.1 self-test entry point for the embedded OpenJDK Zero VM.
//
// Boots the VM once (if needed) on a dedicated large-stack thread — iOS's 512 KB
// default is far too small for HotSpot — loads the bundled Keiyoushi extension jar
// against the Suwayomi host, calls getPopularManga, and delivers the human-readable
// report back on the main queue. The heavy lifting lives in Java (ExtHarness.probe /
// SourceRunner) so this native shim stays tiny.
//
// When the app is built WITHOUT -DFOXLATIONS_JVM (i.e. the normal production build),
// this links to a stub that immediately reports the integration is disabled — so the
// Runner target compiles and links with no JVM, no static libs, no size cost.
void FoxJvmProbeAsync(void (^completion)(NSString *report));

// M5.2 JSON RPC: hands `reqJson` ({method, jar, lang?, page?, query?, url?}) to
// SourceRunner.invoke on the JVM worker thread and delivers the JSON response on the
// main queue. Boots the VM on first use. Stub returns an {"error":...} JSON in a
// non-JVM build.
void FoxJvmInvokeAsync(NSString *reqJson, void (^completion)(NSString *responseJson));

#endif /* FOXLATIONS_JVMBRIDGE_H */
