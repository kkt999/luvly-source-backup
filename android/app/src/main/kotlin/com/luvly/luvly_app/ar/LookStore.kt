package com.luvly.luvly_app.ar

import java.io.File
import java.io.OutputStream
import java.util.Properties
import java.util.UUID

data class SavedLook(val id: String,val dressId: String,val savedAt: Long,
                     val fullBody: Boolean,val path: String) {
    fun toMap(): Map<String,Any> = mapOf("id" to id,"dressId" to dressId,
        "savedAt" to savedAt,"fullBody" to fullBody,"path" to path)
}

/** Explicit saves only. Caller uses noBackupFilesDir, never cloud/shared storage. */
class LookStore(private val directory: File) {
    companion object { private val safeId=Regex("[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}") }
    private fun file(id: String,extension: String): File {
        require(safeId.matches(id)) { "Invalid look identifier" }
        return File(directory,"$id.$extension")
    }
    fun list(): List<SavedLook> = directory.listFiles()?.filter { it.extension=="properties" }
        ?.mapNotNull { metadata -> runCatching {
            val id=metadata.nameWithoutExtension
            val picture=file(id,"png")
            check(picture.isFile)
            val p=Properties().apply { metadata.inputStream().use { load(it) } }
            val dressId=p.getProperty("dressId")
            check(ArDressCatalogue.byId(dressId)!=null)
            SavedLook(id,dressId,p.getProperty("savedAt").toLong(),
                p.getProperty("fullBody")=="true",picture.absolutePath)
        }.getOrNull() }?.sortedByDescending { it.savedAt } ?: emptyList()

    @Synchronized fun save(dressId: String,fullBody: Boolean,writeImage: (OutputStream)->Unit): SavedLook {
        require(ArDressCatalogue.byId(dressId)!=null)
        check(list().size<50) { "Your 50-look album is full. Delete a look before saving another." }
        check(directory.isDirectory || directory.mkdirs()) { "Storage is unavailable" }
        val id=UUID.randomUUID().toString();val now=System.currentTimeMillis()
        val temporary=file(id,"tmp");val picture=file(id,"png");val metadata=file(id,"properties")
        try {
            temporary.outputStream().use(writeImage)
            check(temporary.length()>0 && temporary.renameTo(picture)) { "Could not save image" }
            Properties().apply {
                setProperty("dressId",dressId);setProperty("savedAt",now.toString())
                setProperty("fullBody",fullBody.toString())
            }.also { p -> metadata.outputStream().use { p.store(it,"Luvly local appearance preview") } }
            return SavedLook(id,dressId,now,fullBody,picture.absolutePath)
        } catch(e: Exception) {
            temporary.delete();picture.delete();metadata.delete();throw e
        }
    }
    @Synchronized fun delete(id: String): Boolean {
        val picture=file(id,"png");val metadata=file(id,"properties")
        if(picture.exists() && !picture.delete())return false
        return !metadata.exists() || metadata.delete()
    }
}
