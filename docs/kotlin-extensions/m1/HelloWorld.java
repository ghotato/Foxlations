// M1 smoke test: the simplest possible class the embedded iOS JVM runs.
// The launcher (jvmboot_main.m) also reads java.version via JNI directly, so
// even if System.out isn't visible on-device, we still get a pass/fail signal.
public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("HelloWorld.main ran on "
            + System.getProperty("java.vm.name") + " "
            + System.getProperty("java.version"));
    }
}
