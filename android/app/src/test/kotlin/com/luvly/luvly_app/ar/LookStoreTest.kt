package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import org.junit.rules.TemporaryFolder
class LookStoreTest {
    @get:Rule val temp=TemporaryFolder()
    @Test fun savesListsAndDeletesOnlyExplicitLook() {
        val s=LookStore(temp.newFolder())
        val a=s.save("princess-wedding",false) { it.write(byteArrayOf(1,2,3)) }
        val b=s.save("francine-reference",true) { it.write(byteArrayOf(4,5)) }
        assertEquals(2,s.list().size);assertFalse(a.fullBody)
        assertTrue(s.delete(a.id));assertEquals(b.id,s.list().single().id)
    }
    @Test fun failedWriteDoesNotLeaveAnAlbumEntry() {
        val dir=temp.newFolder();val s=LookStore(dir)
        try { s.save("princess-wedding",true) { throw java.io.IOException() };fail() }
        catch(_:java.io.IOException) {}
        assertTrue(s.list().isEmpty());assertEquals(0,dir.listFiles()!!.size)
    }
    @Test fun rejectsPathTraversalAndUnmappedDress() {
        val s=LookStore(temp.newFolder())
        try { s.delete("../outside");fail() }catch(_:IllegalArgumentException) {}
        try { s.save("unmapped",true) { it.write(1) };fail() }catch(_:IllegalArgumentException) {}
    }
}
