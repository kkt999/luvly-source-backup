package com.luvly.luvly_app.ar

import android.app.Activity
import android.graphics.*
import android.os.*
import android.view.*
import android.widget.*
import java.io.File
import kotlin.math.*

/** Paired isolated mesh rendering. No camera, account, or network access. */
class SkirtDrapeFixtureActivity:Activity(),Choreographer.FrameCallback {
    private val handler=Handler(Looper.getMainLooper())
    private lateinit var texture:TextureView
    private lateinit var label:TextView
    private var renderer:DressRenderer?=null
    private var running=false
    private var index=0
    private val report=StringBuilder("Synthetic poses; same asset/lighting/pose, only skirt weights differ.\n")
    private val stages=listOf(0f to 0f,0f to .25f,45f to .25f,90f to .25f,0f to -.25f, -45f to -.25f)
    override fun onCreate(state:Bundle?) {
        super.onCreate(state)
        texture=TextureView(this).apply {isOpaque=false}
        label=TextView(this).apply {text="Skirt render check · Camera off";setTextColor(Color.WHITE);setBackgroundColor(Color.BLACK)}
        val stage=FrameLayout(this).apply {setBackgroundColor(Color.rgb(80,84,87))}
        stage.addView(texture,FrameLayout.LayoutParams(-1,-1));stage.addView(label);setContentView(stage)
        val dress=ArDressCatalogue.byId("princess-wedding")!!
        renderer=DressRenderer(this,texture,dress.asset,dress.anchors)
        handler.postDelayed({next()},1500)
    }
    private fun next() {
        if(isDestroyed)return
        if(index>=stages.size*2) {
            File(filesDir,"skirt-drape-result.txt").writeText(report.toString()+"COMPLETE\n")
            label.text="Render check complete · Camera off";return
        }
        val (yaw,roll)=stages[index/2];val after=index%2==1
        val a=Math.toRadians(yaw.toDouble()).toFloat()
        val spatial=SpatialDressPose(Vec3(0f,0f,-2f),Vec3(cos(a),0f,-sin(a)),Vec3(0f,1f,0f),1f,1f,
            PerspectiveProjection(texture.width,texture.height,800f,800f,texture.width/2f,texture.height/2f,"fixture"),0f)
        val scale=min(texture.width/2.8f,texture.height/2f)
        val pose=DressPose(texture.width*.5f,texture.height*.74f,scale,scale,roll,spatial=spatial,unprojectedWidth=true)
        renderer?.update(pose,1f,after)
        label.text="Synthetic pose · yaw $yaw · lean $roll · ${if(after)"new drape" else "previous rigid skirt"}"
        handler.postDelayed({
            texture.bitmap?.let {bitmap->
                val pixels=IntArray(bitmap.width*bitmap.height);bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height)
                val count=pixels.count {Color.alpha(it)>32}
                report.appendLine("stage=${index/2} after=$after opaquePixels=$count")
                File(filesDir,"skirt-${index/2}-${if(after)"after" else "before"}.png").outputStream().use {bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
                bitmap.recycle()
            } ?: report.appendLine("ERROR missing bitmap $index")
            index++;next()
        },1200)
    }
    override fun onResume(){super.onResume();running=true;Choreographer.getInstance().postFrameCallback(this)}
    override fun onPause(){running=false;Choreographer.getInstance().removeFrameCallback(this);super.onPause()}
    override fun doFrame(time:Long){if(running){renderer?.render(time);Choreographer.getInstance().postFrameCallback(this)}}
    override fun onDestroy(){running=false;handler.removeCallbacksAndMessages(null);renderer?.close();super.onDestroy()}
}
