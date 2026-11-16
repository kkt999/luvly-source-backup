package com.luvly.luvly_app.ar

import java.io.File
import java.security.MessageDigest

/** An account cannot inherit the previous installation-wide album. No migration or deletion. */
object AccountLookDirectory {
    fun forUid(root: File, uid: String): File {
        require(uid.isNotBlank()) { "Sign in before accessing saved looks" }
        val key = MessageDigest.getInstance("SHA-256").digest(uid.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        return File(File(root, "account_ar_looks"), key)
    }
}
