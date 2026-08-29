// A trivial "plugin" packaged into probe.jar and loaded at RUNTIME (not on the
// boot classpath) by ExtHarness via URLClassLoader. If its greet() runs on the
// device, the Zero VM can load and execute arbitrary downloaded jar bytecode —
// the foundational capability every Kotlin manga extension relies on.
public final class TestPlugin {
    public static String greet() {
        return "TestPlugin ran (dynamic jar bytecode executes in Zero-on-iOS)";
    }
    private TestPlugin() {}
}
