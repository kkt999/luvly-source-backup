package com.luvly.luvly_app.ar

import android.content.Context
import android.content.Intent
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest

/** A model downloaded by the signed-in Flutter client for a single try-on. */
internal object GeneratedDressFile {
    private const val prefix = "generated-"
    private val dressId = Regex("[A-Za-z0-9_-]{1,150}")
    private val filename = Regex("generated-[0-9]+\\.glb")
    private const val limit = 12 * 1024 * 1024
    // The approved V-neck mesh has a 0.27 m shoulder span at y=1.32 m.
    // Match the exact asset so replacements and other necklines use their own fit.
    private val reviewedMesh = "4e6bead6becb0de97a3ed6d39e13beca7ff2c75359357485b5576304e57928a4"
        .chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    private val reviewedFit = DressAnchors(
        shoulderY = 1.39f, hipY = .87f, shoulderWidth = .31f, lightScale = 1.35f)

    fun isGenerated(id: String?): Boolean =
        id != null && id.startsWith(prefix) && dressId.matches(id.removePrefix(prefix))

    private fun directory(context: Context) = File(context.cacheDir, "generated-gowns")

    fun stage(context: Context, id: String?, label: String?, bytes: ByteArray?): Intent {
        require(id != null && dressId.matches(id))
        require(label != null && label.isNotBlank() && label.length <= 100 && label.none { it.isISOControl() })
        require(bytes != null && bytes.size in 32..limit)
        val header = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        require(header.int == 0x46546c67 && header.int == 2 && header.int == bytes.size)
        val calibrated = MessageDigest.getInstance("SHA-256").digest(bytes).contentEquals(reviewedMesh)
        val directory = directory(context)
        check(directory.isDirectory || directory.mkdirs())
        val expireBefore = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
        directory.listFiles()?.filter { filename.matches(it.name) && it.lastModified() < expireBefore }
            ?.forEach { it.delete() }
        val file = File.createTempFile(prefix, ".glb", directory)
        try {
            file.writeBytes(bytes)
            return Intent(context, TryOnActivity::class.java)
                .putExtra("dressId", prefix + id)
                .putExtra("generatedModel", file.name)
                .putExtra("generatedLabel", label)
                .putExtra("generatedReviewedFit", calibrated)
        } catch (error: Exception) {
            file.delete()
            throw error
        }
    }

    private fun file(context: Context, name: String): File {
        require(filename.matches(name))
        return File(directory(context), name)
    }

    fun resolve(context: Context, intent: Intent): ArDress? {
        val id = intent.getStringExtra("dressId") ?: return null
        val name = intent.getStringExtra("generatedModel") ?: return null
        val label = intent.getStringExtra("generatedLabel") ?: return null
        if (!isGenerated(id) || label.isBlank() || label.length > 100 ||
            !filename.matches(name) || !file(context, name).isFile) return null
        val anchors = if (intent.getBooleanExtra("generatedReviewedFit", false)) reviewedFit else DressAnchors()
        return ArDress(id, name, label, anchors, style = "Generated 3D model")
    }

    fun read(context: Context, name: String): ByteBuffer {
        val source = file(context, name)
        check(source.length() in 32..limit.toLong())
        val bytes = source.readBytes()
        return ByteBuffer.allocateDirect(bytes.size).apply { put(bytes); flip() }
    }

    fun remove(context: Context, name: String) { file(context, name).delete() }
}
