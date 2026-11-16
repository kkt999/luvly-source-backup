package com.luvly.luvly_app.ar

import android.app.Activity
import android.graphics.*
import android.os.*
import android.view.*
import android.widget.*
import java.io.File
import kotlin.math.*

/** Camera-free device check of the cropped-shoulder registration and renderer. */
class UpperBodyFixtureActivity: Activity(), Choreographer.FrameCallback {
    private val handler=Handler(Looper.getMainLooper())
    private lateinit var texture: TextureView
    private lateinit var label: TextView
    private var renderer: DressRenderer?=null
    private var running=false
    private var index=0
    private val result=StringBuilder("Synthetic shoulder poses; camera off.\n")
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        texture=TextureView(this).apply { isOpaque=false }
        label=TextView(this).apply { setTextColor(Color.WHITE);setBackgroundColor(Color.BLACK) }
        setContentView(FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(80,84,87))
            addView(texture,FrameLayout.LayoutParams(-1,-1));addView(label)
        })
        val dress=ArDressCatalogue.byId("princess-wedding")!!
        renderer=DressRenderer(this,texture,dress.asset,dress.anchors)
        handler.postDelayed({ next() },1500)
    }
    private fun next() {
        if(isDestroyed)return
        if(index>=5) {
            File(filesDir,"upper-body-result.txt").writeText(result.toString()+"COMPLETE\n")
            label.text="Upper-body render check complete · Camera off";return
        }
        val yaw=listOf(0f,30f,-30f,0f,0f)[index]
        val angle=Math.toRadians(yaw.toDouble()).toFloat()
        val p=MutableList(33) { BodyPoint(.5f,.2f,0f) }.apply {
            this[0]=BodyPoint(.5f,.23f,1f)
            this[2]=BodyPoint(.46f,.20f,1f);this[5]=BodyPoint(.54f,.20f,1f)
            this[11]=BodyPoint(.5f-.28f*cos(angle),.48f,1f)
            this[12]=BodyPoint(.5f+.28f*cos(angle),.48f,1f)
            this[23]=BodyPoint(.35f,1.1f,.1f);this[24]=BodyPoint(.65f,1.1f,.1f)
        }
        val w=MutableList(33) { WorldBodyPoint(0f,0f,0f,0f) }.apply {
            this[11]=WorldBodyPoint(-.2f*cos(angle),-.4f,-.2f*sin(angle),1f)
            this[12]=WorldBodyPoint(.2f*cos(angle),-.4f,.2f*sin(angle),1f)
        }
        if(index>=3) {
            p[13]=BodyPoint(.25f,.65f,1f);p[14]=BodyPoint(.75f,.65f,1f)
            w[13]=if(index==4)WorldBodyPoint(-.4f,-.3f,-.1f,1f)
                else WorldBodyPoint(-.2f,-.1f,0f,1f)
            w[14]=WorldBodyPoint(.2f,-.1f,0f,1f)
        }
        val pose=UpperBodyPreview().register(p,w,600,900,texture.width,texture.height,
            ArDressCatalogue.byId("princess-wedding")!!.anchors,FrameProjection.estimated(600,900),1000)
        renderer?.update(pose,1f)
        label.text="Upper-body preview · synthetic $yaw degrees · Camera off"
        handler.postDelayed({
            texture.bitmap?.let { bitmap ->
                val pixels=IntArray(bitmap.width*bitmap.height)
                bitmap.getPixels(pixels,0,bitmap.width,0,0,bitmap.width,bitmap.height)
                result.appendLine("case=$index yaw=$yaw registered=${pose!=null} visiblePixels=${pixels.count {Color.alpha(it)>32}} sleeveLeft=${pose?.sleeveLeft} sleeveRight=${pose?.sleeveRight}")
                File(filesDir,"upper-body-$index.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) }
                bitmap.recycle()
            } ?: result.appendLine("ERROR no render $index")
            index++;next()
        },1200)
    }
    override fun onResume(){super.onResume();running=true;Choreographer.getInstance().postFrameCallback(this)}
    override fun onPause(){running=false;Choreographer.getInstance().removeFrameCallback(this);super.onPause()}
    override fun doFrame(time:Long){if(running){renderer?.render(time);Choreographer.getInstance().postFrameCallback(this)}}
    override fun onDestroy(){running=false;handler.removeCallbacksAndMessages(null);renderer?.close();super.onDestroy()}
}
