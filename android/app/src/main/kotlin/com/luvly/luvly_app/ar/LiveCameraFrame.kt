package com.luvly.luvly_app.ar

import android.graphics.Bitmap
import android.graphics.Matrix

/** One full-frame transform shared by live camera and camera-free device tests.
 * Caller owns input/output; createBitmap may return input for an identity transform. */
internal object LiveCameraFrame {
    fun orient(raw: Bitmap,rotation: Int,mirror: Boolean): Bitmap {
        val scale=minOf(1f,640f/maxOf(raw.width,raw.height))
        val matrix=Matrix().apply {
            postRotate(rotation.toFloat())
            postScale(if(mirror)-scale else scale,scale)
        }
        return Bitmap.createBitmap(raw,0,0,raw.width,raw.height,matrix,true)
    }
}
