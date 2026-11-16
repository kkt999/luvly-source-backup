package com.luvly.luvly_app.ar

import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage

/** MPImage.close() recycles its source bitmap in MediaPipe 0.10.21.
 * Preview pixels must remain independently owned by the camera UI. */
internal fun <T> withBodyScanImage(preview: Bitmap, detect: (MPImage)->T): T {
    val inference=preview.copy(Bitmap.Config.ARGB_8888,false) ?: error("Could not copy scan image")
    val input=try{BitmapImageBuilder(inference).build()}catch(e:Exception){inference.recycle();throw e}
    return try{detect(input)}finally{input.close()}
}
