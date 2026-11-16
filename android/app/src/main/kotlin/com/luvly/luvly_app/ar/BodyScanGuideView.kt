package com.luvly.luvly_app.ar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.View

/** Visual coaching only. Ratios still use full camera image coordinates.
 * Match FIT_CENTER preview bounds so the guide never refers to letterbox bars. */
internal class BodyScanGuideView(context: Context, private val fullBody: Boolean=false): View(context) {
    private val line=Paint(Paint.ANTI_ALIAS_FLAG).apply {style=Paint.Style.STROKE;strokeWidth=2.5f*resources.displayMetrics.density;color=Color.WHITE;alpha=190}
    private val shade=Paint().apply {color=Color.argb(45,0,0,0)}
    private var imageWidth=480
    private var imageHeight=640
    fun updateFrame(w: Int,h: Int,collecting: Boolean){
        imageWidth=w;imageHeight=h
        line.color=if(collecting)Color.rgb(153,231,195) else Color.WHITE
        invalidate()
    }
    override fun onDraw(canvas: Canvas){
        super.onDraw(canvas)
        if(width<=0 || height<=0 || imageWidth<=0 || imageHeight<=0)return
        val scale=minOf(width.toFloat()/imageWidth,height.toFloat()/imageHeight)
        val w=imageWidth*scale;val h=imageHeight*scale
        val left=(width-w)/2;val top=(height-h)/2
        val bounds=RectF(left+w*.12f,top+h*.10f,left+w*.88f,top+h*.91f)
        canvas.drawRect(left,top,left+w,bounds.top,shade)
        canvas.drawRect(left,bounds.bottom,left+w,top+h,shade)
        canvas.drawRect(left,bounds.top,bounds.left,bounds.bottom,shade)
        canvas.drawRect(bounds.right,bounds.top,left+w,bounds.bottom,shade)
        line.pathEffect=null
        canvas.drawRoundRect(bounds,20f,20f,line)
        if(fullBody)return
        line.pathEffect=DashPathEffect(floatArrayOf(10f,12f),0f)
        // A head-to-hip silhouette encourages less ceiling and a level phone.
        canvas.drawOval(RectF(left+w*.43f,top+h*.17f,left+w*.57f,top+h*.31f),line)
        val torso=Path().apply{
            moveTo(left+w*.46f,top+h*.33f)
            lineTo(left+w*.32f,top+h*.39f);lineTo(left+w*.35f,top+h*.72f)
            lineTo(left+w*.31f,top+h*.82f)
            moveTo(left+w*.54f,top+h*.33f)
            lineTo(left+w*.68f,top+h*.39f);lineTo(left+w*.65f,top+h*.72f)
            lineTo(left+w*.69f,top+h*.82f)
        }
        canvas.drawPath(torso,line)
        canvas.drawLine(left+w*.31f,top+h*.82f,left+w*.69f,top+h*.82f,line)
        line.pathEffect=null
    }

}
