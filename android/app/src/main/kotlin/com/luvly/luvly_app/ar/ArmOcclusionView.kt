package com.luvly.luvly_app.ar

import android.content.Context
import android.graphics.*
import android.view.View
import kotlin.math.*

/** Exact camera pixels, limited by both foreground arm geometry AND segmented skin. */
class ArmOcclusionView(context: Context): View(context) {
    private var source: Bitmap?=null
    private var mask: Bitmap?=null
    private val paint=Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val maskPaint=Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
        xfermode=PorterDuffXfermode(PorterDuff.Mode.DST_IN)
    }

    fun update(bitmap: Bitmap?,alphaMask: Bitmap?=null) {
        source=bitmap;mask=alphaMask;invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val bitmap=source ?: return
        val alpha=mask ?: return
        if(bitmap.isRecycled || alpha.isRecycled)return
        val scale=min(width.toFloat()/bitmap.width,height.toFloat()/bitmap.height)
        canvas.save()
        canvas.translate((width-bitmap.width*scale)/2,(height-bitmap.height*scale)/2)
        canvas.scale(scale,scale)
        val rect=RectF(0f,0f,bitmap.width.toFloat(),bitmap.height.toFloat())
        canvas.saveLayer(rect,null)
        canvas.drawBitmap(bitmap,0f,0f,paint)
        canvas.drawBitmap(alpha,null,rect,maskPaint)
        canvas.restore();canvas.restore()
    }
}
