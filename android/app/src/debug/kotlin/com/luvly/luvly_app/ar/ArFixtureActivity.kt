package com.luvly.luvly_app.ar

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.graphics.*
import android.view.*
import android.widget.FrameLayout
import java.io.File

/** Debug-only, camera-free deterministic renderer verification on the target GPU. */
class ArFixtureActivity: Activity(), Choreographer.FrameCallback {
    private lateinit var texture: TextureView
    private lateinit var background: View
    private var dress: DressRenderer?=null
    private var running=false
    private var poseApplied=false
    private var nextReattach=0L
    private var reattachments=0
    private val reattachChecks=mutableListOf<String>()
    private val captureHandler=Handler(Looper.getMainLooper())
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val frame=FrameLayout(this)
        background=object: View(this) {
            override fun onDraw(c: Canvas) {
                c.drawColor(Color.rgb(224,228,231))
                val s=minOf(width/600f,height/900f)
                c.save(); c.translate((width-600*s)/2,(height-900*s)/2); c.scale(s,s)
                val p=Paint(Paint.ANTI_ALIAS_FLAG).apply {color=Color.rgb(60,125,130)}
                c.drawOval(258f,85f,342f,180f,p)
                val torso=Path().apply {moveTo(277f,177f);lineTo(277f,211f);lineTo(180f,225f)
                    lineTo(199f,310f);lineTo(214f,414f);lineTo(210f,495f);lineTo(390f,495f)
                    lineTo(386f,414f);lineTo(401f,310f);lineTo(420f,225f);lineTo(323f,211f)
                    lineTo(323f,177f);close()}
                c.drawPath(torso,p)
                p.strokeWidth=42f;p.strokeCap=Paint.Cap.ROUND
                c.drawLine(180f,246f,154f,416f,p);c.drawLine(154f,416f,151f,580f,p)
                c.drawLine(420f,246f,446f,416f,p);c.drawLine(446f,416f,449f,580f,p)
                c.drawLine(255f,480f,251f,817f,p);c.drawLine(345f,480f,349f,817f,p)
                p.color=Color.DKGRAY;p.textSize=16f;p.strokeWidth=1f
                c.drawText("Synthetic pose • no camera • same Android renderer",70f,50f,p)
                c.restore()
            }
        }
        texture=TextureView(this).apply {isOpaque=false}
        frame.addView(background,FrameLayout.LayoutParams(-1,-1))
        frame.addView(texture,FrameLayout.LayoutParams(-1,-1));setContentView(frame)
        val d=ArDressCatalogue.resolve("princess-wedding","assets/models/princess_wedding.glb")!!
        dress=DressRenderer(this,texture,d.asset,d.anchors.copy(
            adaptiveFit=intent.getBooleanExtra("adaptiveFit",true)),
            if(intent.getBooleanExtra("vulkan",false)) com.google.android.filament.Engine.Backend.VULKAN
            else com.google.android.filament.Engine.Backend.DEFAULT)
        captureHandler.postDelayed({
            if(!running)return@postDelayed
            texture.bitmap?.let { layer ->
                val result=Bitmap.createBitmap(texture.width,texture.height,Bitmap.Config.ARGB_8888)
                val canvas=Canvas(result);background.draw(canvas);canvas.drawBitmap(layer,0f,0f,null)
                File(filesDir,"ar_fixture.png").outputStream().use {result.compress(Bitmap.CompressFormat.PNG,100,it)}
                result.recycle();layer.recycle()
            }
        },12000)
    }
    override fun onResume() {
        super.onResume()
        running=true;Choreographer.getInstance().postFrameCallback(this)
    }
    override fun onPause() {
        running=false;Choreographer.getInstance().removeFrameCallback(this)
        super.onPause()
    }
    override fun doFrame(time: Long) {
        if(!running)return
        if(intent.getBooleanExtra("reattachTest",false) && texture.isAvailable) {
            val now=android.os.SystemClock.uptimeMillis()
            if(nextReattach==0L)nextReattach=now+2500
            if(now>=nextReattach && reattachments<3) {
                dress?.close();dress=null
                val d=ArDressCatalogue.byId("princess-wedding")!!
                dress=DressRenderer(this,texture,d.asset,d.anchors)
                reattachments++;poseApplied=false;nextReattach=now+2500
                reattachChecks.add("PASS attach to already-available texture $reattachments: ${texture.width} x ${texture.height}")
            } else if(reattachments==3 && now>=nextReattach) {
                texture.bitmap?.let { bitmap ->
                    val visible=(0 until bitmap.height step 30).any { y ->
                        (0 until bitmap.width step 30).any { x -> Color.alpha(bitmap.getPixel(x,y))>32 }
                    }
                    bitmap.recycle()
                    reattachChecks.add("${if(visible)"PASS" else "FAIL"} overlay renders after three reattachments")
                }
                File(filesDir,"ar_reattach_result.txt").writeText("Completed: ${System.currentTimeMillis()}\n"+reattachChecks.joinToString("\n"))
                reattachments++
            }
        }
        if(!poseApplied && texture.width>0 && texture.height>0 && texture.isAvailable) {
            val d=ArDressCatalogue.resolve("princess-wedding","assets/models/princess_wedding.glb")!!
            val points=MutableList(33){BodyPoint(.5f,.5f,1f)}
            points[11]=BodyPoint(.3f,.25f,1f);points[12]=BodyPoint(.7f,.25f,1f)
            points[23]=BodyPoint(.4f,.50f,1f);points[24]=BodyPoint(.6f,.50f,1f)
            val pose=checkNotNull(PoseAlignment.align(points,600,900,texture.width,texture.height,d.anchors))
            dress?.update(pose,1f);poseApplied=true
        }
        dress?.render(time);Choreographer.getInstance().postFrameCallback(this)
    }
    override fun onDestroy() {
        captureHandler.removeCallbacksAndMessages(null)
        running=false;Choreographer.getInstance().removeFrameCallback(this)
        dress?.close();super.onDestroy()
    }
}
