package com.luvly.luvly_app.ar

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.MotionEvent
import java.io.File
import org.json.JSONObject

/** Debug-only GPU acceptance fixture. No camera, network, customer files or saved looks. */
class GownViewerFixtureActivity: GownViewerActivity() {
    private val timer=Handler(Looper.getMainLooper())
    private val result=JSONObject()
    private var modelId="princess-wedding"
    override fun canOpen()=true
    override fun onCreate(state: Bundle?) {
        modelId=intent.getStringExtra("fixtureDressId") ?: "princess-wedding"
        val chosen=ArDressCatalogue.byId(modelId)
        if(chosen==null){super.onCreate(state);finish();return}
        intent.putExtra("dressId",chosen.id)
        intent.putExtra("modelAsset",chosen.asset)
        result.put("modelId",modelId)
        super.onCreate(state)
    }
    override fun onModelReady() {
        timer.postDelayed({ capture("front");selectView("Back view") },1800)
        timer.postDelayed({ capture("back");zoomBy(1.8) },3000)
        timer.postDelayed({ capture("zoom");selectView("Reset") },4200)
        timer.postDelayed({
            capture("reset")
            drag()
        },5400)
        timer.postDelayed({ capture("drag");selectView("Reset");pinch() },6600)
        timer.postDelayed({
            capture("pinch")
            File(filesDir,"gown-viewer-2103-$modelId-result.json").writeText(result.toString(2))
        },7800)
    }
    private fun drag() {
        val time=SystemClock.uptimeMillis()
        for((i,action) in listOf(MotionEvent.ACTION_DOWN,MotionEvent.ACTION_MOVE,MotionEvent.ACTION_UP).withIndex()) {
            val x=texture.width*(if(i==0).4f else .65f)
            val event=MotionEvent.obtain(time,time+i*20,action,x,texture.height*.5f,0)
            texture.dispatchTouchEvent(event);event.recycle()
        }
    }
    private fun pinch() {
        val time=SystemClock.uptimeMillis()
        val actions=listOf(MotionEvent.ACTION_DOWN,MotionEvent.ACTION_POINTER_DOWN or (1 shl 8),
            MotionEvent.ACTION_MOVE,MotionEvent.ACTION_MOVE,MotionEvent.ACTION_MOVE,
            MotionEvent.ACTION_POINTER_UP or (1 shl 8),MotionEvent.ACTION_UP)
        for((i,action) in actions.withIndex()) {
            val count=if(i==0 || i==6)1 else 2
            val span=texture.width*(if(i<2).18f else if(i==2).28f else if(i==3).38f else .48f)
            val properties=Array(count){index->MotionEvent.PointerProperties().apply {id=index;toolType=MotionEvent.TOOL_TYPE_FINGER}}
            val coordinates=Array(count){index->MotionEvent.PointerCoords().apply {
                x=texture.width*.5f+(if(index==0)-span else span);y=texture.height*.5f;pressure=1f;size=1f
            }}
            val event=MotionEvent.obtain(time,time+i*20,action,count,properties,coordinates,0,0,1f,1f,0,0,android.view.InputDevice.SOURCE_TOUCHSCREEN,0)
            texture.dispatchTouchEvent(event);event.recycle()
        }
    }
    private fun capture(name: String) {
        if(isFinishing || isDestroyed)return
        val layer=texture.bitmap ?: return
        val pixels=IntArray(layer.width*layer.height);layer.getPixels(pixels,0,layer.width,0,0,layer.width,layer.height)
        result.put(name,JSONObject().put("width",layer.width).put("height",layer.height)
            .put("visiblePixels",pixels.count { (it ushr 24)>30 }).put("hash",pixels.contentHashCode())
            .put("camera",org.json.JSONArray(cameraState().toList())))
        val root=window.decorView
        val shot=Bitmap.createBitmap(root.width,root.height,Bitmap.Config.ARGB_8888)
        val canvas=Canvas(shot);root.draw(canvas)
        val position=IntArray(2);texture.getLocationInWindow(position)
        canvas.drawBitmap(layer,position[0].toFloat(),position[1].toFloat(),null)
        File(filesDir,"gown-viewer-2103-$modelId-$name.png").outputStream().use { shot.compress(Bitmap.CompressFormat.PNG,100,it) }
        layer.recycle();shot.recycle()
    }
    override fun onDestroy() { timer.removeCallbacksAndMessages(null);super.onDestroy() }
}
