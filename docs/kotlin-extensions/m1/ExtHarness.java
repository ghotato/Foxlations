import java.io.File;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * On-device harness invoked from the Objective-C launcher via JNI once the Zero VM
 * is up. Returns a human-readable report shown on screen and logged to jvmboot.txt.
 *
 *  M2 [1] URLClassLoader + reflection execute bytecode from a runtime jar.
 *  M2 [2] a real Keiyoushi 1.6 extension jar is opened + its manifest read.
 *  M3/M4a [3] the extension is loaded against the Suwayomi host jar (extensions-lib
 *         + AndroidCompat + OkHttp) and instantiated, then handed to SourceRunner
 *         (Kotlin, in runner.jar) which bootstraps a minimal DB-free Suwayomi host
 *         and calls the source's suspend getPopularManga(1) to FETCH real manga.
 *
 * Classloader topology (matters): a `hostCl` over [suwayomi.jar, runner.jar] provides
 * all host classes + SourceRunner; the extension loads in a child `extCl` so its
 * KeiSource/HttpSource resolve from the host — keeping the instantiated Source and
 * SourceRunner's CatalogueSource on the same loader (castable).
 */
public final class ExtHarness {

    public static String probe(String probeJarPath, String extJarPath,
                               String suwayomiJarPath, String workDir) {
        StringBuilder sb = new StringBuilder();

        // [1] Run self-authored bytecode from a jar loaded at runtime.
        sb.append("[1] URLClassLoader run\n");
        try {
            File pj = new File(probeJarPath);
            sb.append("  probe.jar exists=").append(pj.exists()).append('\n');
            if (pj.exists()) {
                try (URLClassLoader cl = new URLClassLoader(
                        new URL[]{ pj.toURI().toURL() }, ExtHarness.class.getClassLoader())) {
                    Class<?> c = Class.forName("TestPlugin", true, cl);
                    sb.append("  OK: ").append(c.getMethod("greet").invoke(null)).append('\n');
                }
            }
        } catch (Throwable t) {
            sb.append("  FAIL: ").append(t).append('\n');
        }

        // [2] Inspect the real extension jar.
        sb.append("[2] Keiyoushi extension jar\n");
        File ej = new File(extJarPath);
        if (!ej.exists()) { sb.append("  (none bundled)\n"); return sb.toString(); }
        String entryClass = null;
        try {
            sb.append("  file=").append(ej.getName()).append(" size=").append(ej.length()).append('\n');
            int classCount = 0;
            try (ZipFile zf = new ZipFile(ej)) {
                ZipEntry man = zf.getEntry("AndroidManifest.xml");
                if (man != null) {
                    String xml = new String(zf.getInputStream(man).readAllBytes(), StandardCharsets.UTF_8);
                    sb.append("  ").append(pluck(xml, "tachiyomix.extensionLib")).append('\n');
                }
                Enumeration<? extends ZipEntry> e = zf.entries();
                while (e.hasMoreElements()) {
                    String n = e.nextElement().getName();
                    if (n.endsWith(".class")) {
                        classCount++;
                        if (n.endsWith("ExtensionGenerated.class")) {
                            entryClass = n.substring(0, n.length() - ".class".length()).replace('/', '.');
                        }
                    }
                }
            }
            sb.append("  .class entries=").append(classCount).append(" entry=").append(entryClass).append('\n');
        } catch (Throwable t) {
            sb.append("  inspect FAIL: ").append(t).append('\n');
            return sb.toString();
        }

        // [3] Load+instantiate against the Suwayomi host, then [4] fetch via SourceRunner.
        sb.append("[3] host link + [4] fetch\n");
        if (entryClass == null) { sb.append("  (no ExtensionGenerated — legacy 1.4)\n"); return sb.toString(); }
        try {
            File sj = new File(suwayomiJarPath);
            File rj = new File(sj.getParentFile(), "runner.jar");   // sibling in jars/
            sb.append("  suwayomi=").append(sj.exists()).append(" runner=").append(rj.exists()).append('\n');
            if (!sj.exists() || !rj.exists()) { sb.append("  missing host/runner jar\n"); return sb.toString(); }

            URLClassLoader hostCl = new URLClassLoader(
                new URL[]{ sj.toURI().toURL(), rj.toURI().toURL() }, ExtHarness.class.getClassLoader());
            URLClassLoader extCl = new URLClassLoader(new URL[]{ ej.toURI().toURL() }, hostCl);

            Object src;
            try {
                Class<?> ec = Class.forName(entryClass, false, extCl);
                src = ec.getDeclaredConstructor().newInstance();
                sb.append("  INSTANTIATED ").append(src.getClass().getSimpleName())
                  .append(" isSource=").append(isA(hostCl, src, "eu.kanade.tachiyomi.source.Source")).append('\n');
            } catch (Throwable t) {
                sb.append("  link/instantiate stops at: ").append(rootMsg(t)).append('\n');
                return sb.toString();
            }

            try {
                Class<?> runner = Class.forName("foxtensions.runner.SourceRunner", true, hostCl);
                Method run = runner.getMethod("run", Object.class, String.class);
                sb.append(String.valueOf(run.invoke(null, src, workDir))).append('\n');
            } catch (Throwable t) {
                sb.append("  runner invoke FAIL: ").append(rootMsg(t)).append('\n');
            }
        } catch (Throwable t) {
            sb.append("  [3/4] FAIL: ").append(t).append('\n');
        }
        return sb.toString();
    }

    private static boolean isA(ClassLoader cl, Object o, String fq) {
        try { return Class.forName(fq, false, cl).isInstance(o); }
        catch (Throwable t) { return false; }
    }

    private static String rootMsg(Throwable t) {
        Throwable r = t;
        while (r.getCause() != null && r.getCause() != r) r = r.getCause();
        return r.toString();
    }

    private static String pluck(String xml, String key) {
        int i = xml.indexOf(key);
        if (i < 0) return key + "=<absent>";
        int end = Math.min(xml.length(), i + 70);
        return xml.substring(i, end).replaceAll("[\\r\\n\\t]+", " ").trim();
    }

    private ExtHarness() {}
}
