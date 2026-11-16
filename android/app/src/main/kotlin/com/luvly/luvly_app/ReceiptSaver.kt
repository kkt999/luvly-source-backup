package com.luvly.luvly_app

import android.app.Activity
import android.content.Intent
import com.google.firebase.auth.FirebaseAuth
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** User-selected SAF destination only. No broad storage permissions or swallowed I/O errors. */
class ReceiptSaver(private val activity: Activity) {
    private var reply: MethodChannel.Result? = null
    private var payload: ByteArray? = null
    private var account: String? = null
    companion object { const val REQUEST = 17031 }
    fun save(call: MethodCall, result: MethodChannel.Result) {
        if(reply!=null){result.error("SAVE_BUSY","A save is already in progress",null);return}
        val uid=FirebaseAuth.getInstance().currentUser?.uid
        val filename=call.argument<String>("filename") ?: ""
        val mime=call.argument<String>("mime")
        val bytes=call.argument<ByteArray>("bytes")
        if(uid==null){result.error("AUTH_REQUIRED","Sign in before exporting receipts",null);return}
        val validName=Regex("^Luvly-receipt-[a-f0-9]{32}\\.(pdf|png)$").matches(filename)
        val validType=(mime=="application/pdf" && filename.endsWith(".pdf")) || (mime=="image/png" && filename.endsWith(".png"))
        if(!validName || !validType || bytes==null || bytes.size !in 8..8388608){result.error("INVALID_RECEIPT","Invalid receipt export",null);return}
        reply=result;payload=bytes;account=uid
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE).setType(mime)
                .putExtra(Intent.EXTRA_TITLE,filename),REQUEST)
        }catch(_:Exception){finishError("SAVE_UNAVAILABLE","Could not open the save dialog")}
    }
    fun onResult(resultCode: Int, data: Intent?) {
        val target=data?.data
        if(resultCode!=Activity.RESULT_OK || target==null){reply?.success(null);clear();return}
        val bytes=payload ?: return
        if(account!=FirebaseAuth.getInstance().currentUser?.uid){finishError("AUTH_CHANGED","Sign in again before exporting");return}
        val pending=reply
        Thread {
            try {
                val stream=activity.contentResolver.openOutputStream(target) ?: throw IllegalStateException()
                stream.use { it.write(bytes);it.flush() }
                activity.runOnUiThread {if(reply===pending){reply?.success(target.toString());clear()}}
            }catch(_:Exception){activity.runOnUiThread {if(reply===pending)finishError("SAVE_FAILED","Could not write the selected file")}}
        }.start()
    }
    fun dispose(){if(reply!=null)finishError("SAVE_INTERRUPTED","The save screen was closed")}
    private fun finishError(code: String,message: String){reply?.error(code,message,null);clear()}
    private fun clear(){reply=null;payload=null;account=null}
}
