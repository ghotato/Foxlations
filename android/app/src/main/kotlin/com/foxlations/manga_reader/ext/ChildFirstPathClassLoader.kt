package com.foxlations.manga_reader.ext

import dalvik.system.PathClassLoader

/**
 * Parent-LAST classloader (Mihon's `ChildFirstPathClassLoader`). Resolution order is
 * system → the extension APK → parent(host). This lets an extension's own bundled copies
 * of okhttp / kotlin-stdlib / a bundled `NovelSource` win over the host's, which avoids
 * LinkageError / NoSuchMethodError across the ~1000 real extensions that pin their own
 * dependency versions.
 */
class ChildFirstPathClassLoader(
    dexPath: String,
    librarySearchPath: String?,
    parent: ClassLoader,
) : PathClassLoader(dexPath, librarySearchPath, parent) {

    private val system = ClassLoader.getSystemClassLoader()

    override fun loadClass(name: String, resolve: Boolean): Class<*> {
        var clazz = findLoadedClass(name)
        if (clazz == null) {
            clazz = try {
                system.loadClass(name)
            } catch (_: ClassNotFoundException) {
                null
            }
        }
        if (clazz == null) {
            clazz = try {
                findClass(name) // the extension APK first
            } catch (_: ClassNotFoundException) {
                super.loadClass(name, resolve) // then the host (parent)
            }
        }
        if (resolve) resolveClass(clazz)
        return clazz
    }
}
