package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test
import java.io.File

class AccountLookDirectoryTest {
    @Test fun isolatesAccountsAndLegacyAlbum() {
        val root = File("private")
        val a = AccountLookDirectory.forUid(root, "bride-A")
        assertEquals(a, AccountLookDirectory.forUid(root, "bride-A"))
        assertNotEquals(a, AccountLookDirectory.forUid(root, "bride-B"))
        assertNotEquals(a, File(root, "ar_looks"))
        assertEquals(File(root, "account_ar_looks"), a.parentFile)
    }
    @Test fun uidCannotTraverseDirectories() {
        assertTrue(AccountLookDirectory.forUid(File("private"), "../../outside").name.matches(Regex("[a-f0-9]{64}")))
    }
    @Test(expected = IllegalArgumentException::class) fun rejectsEmptyAccount() {
        AccountLookDirectory.forUid(File("private"), "")
    }
}
