package com.luvly.luvly_app.ar

import android.app.Activity
import android.os.*
import android.graphics.*
import android.view.*
import android.widget.*
import com.google.mediapipe.framework.image.BitmapImageBuilder
import java.io.File
import java.util.concurrent.*

/** Offline replay of explicitly supplied frames. No camera or network access.
 * Deterministic render inspection, not live performance / accuracy validation. */
class AppearanceFixtureActivity: Activity(),Choreographer.FrameCallback {
    private lateinit var texture:TextureView
    private lateinit var background:ImageView
    private lateinit var arms:ArmOcclusionView
    private lateinit var label:TextView
    private var renderer:DressRenderer?=null
    private var running=false
    private val handler=Handler(Looper.getMainLooper())
    private val worker=Executors.newSingleThreadExecutor()
    override fun onCreate(state:Bundle?) {
        super.onCreate(state)
        val stage=FrameLayout(this)
        background=ImageView(this).apply { scaleType=ImageView.ScaleType.FIT_CENTER;setBackgroundColor(Color.DKGRAY) }
        texture=TextureView(this).apply {isOpaque=false};arms=ArmOcclusionView(this)
        label=TextView(this).apply {text="Offline recording replay · Camera off";setTextColor(Color.WHITE);setBackgroundColor(Color.BLACK)}
        stage.addView(background,FrameLayout.LayoutParams(-1,-1));stage.addView(texture,FrameLayout.LayoutParams(-1,-1))
        stage.addView(arms,FrameLayout.LayoutParams(-1,-1));stage.addView(label);setContentView(stage)
        val d=ArDressCatalogue.byId("princess-wedding")!!
        val baseline=intent.getBooleanExtra("baseline",false)
        renderer=DressRenderer(this,texture,if(baseline)"local_review/princess_2096.glb" else d.asset,d.anchors)
        handler.postDelayed({ runProbe(baseline) },1800)
    }
    private fun runProbe(baseline:Boolean) {
        val vw=texture.width;val vh=texture.height
        worker.execute {
            val report=StringBuilder("Started ${System.currentTimeMillis()} baseline=$baseline\n")
            val inputs=File(filesDir,"ar_appearance_probe").listFiles()?.filter { it.name.matches(Regex("frame-[0-9]+\\.jpg")) }?.sortedBy { it.name }.orEmpty()
            try {
                check(inputs.isNotEmpty())
                val calibration=BodyTurnCalibration();var time=1000L
                val d=ArDressCatalogue.byId("princess-wedding")!!
                LocalPoseTracker(this).use { tracker->ArmSegmenter(this).use { segmenter->
                    for((index,file)in inputs.withIndex()) {
                        val frame=checkNotNull(BitmapFactory.decodeFile(file.absolutePath))
                        val inference=frame.copy(Bitmap.Config.ARGB_8888,false)
                        val mp=BitmapImageBuilder(inference).build()
                        val result=try { tracker.detect(mp,time) } finally { mp.close();if(!inference.isRecycled)inference.recycle() }
                        val target=result?.landmarks()?.indexOfFirst { p->listOf(11,12,23,24).map {p[it].x()}.average() in .4.. .8 } ?: -1
                        val points=if(target<0)emptyList() else result!!.landmarks()[target].map { BodyPoint(it.x(),it.y(),minOf(it.presence().orElse(0f),it.visibility().orElse(0f)),it.z()) }
                        val world=if(target<0)emptyList() else result!!.worldLandmarks()[target].map {WorldBodyPoint(it.x(),it.y(),it.z(),it.visibility().orElse(0f))}
                        var pose:DressPose?=null
                        repeat(4) { pose=calibration.register(points,world,frame.width,frame.height,vw,vh,d.anchors,FrameProjection.estimated(frame.width,frame.height),time);time+=300 }
                        val mask=if(baseline)null else segmenter.mask(frame,points)
                        report.appendLine("frame=$index pose=${pose!=null} reason=${calibration.rejectionReason} sleeves=${pose?.sleeveLeft}/${pose?.sleeveRight} mask=${segmenter.lastMode} maskMs=${segmenter.lastInferenceMs}")
                        val shown=pose;val latch=CountDownLatch(1)
                        runOnUiThread {
                            if(isDestroyed){ latch.countDown();return@runOnUiThread }
                            val bounds=PoseAlignment.imageBounds(frame.width,frame.height,vw,vh)
                            texture.clipBounds=Rect(bounds[0],bounds[1],bounds[2],bounds[3])
                            background.setImageBitmap(frame);renderer?.update(shown,1f);arms.update(if(shown!=null)frame else null,mask)
                            label.text="Offline replay · ${if(baseline)"2096 material/mesh" else "2097 candidate"} · frame $index"
                            handler.postDelayed({
                                texture.bitmap?.let { layer->
                                    File(filesDir,"appearance-layer-${if(baseline)"before" else "after"}-$index.png").outputStream().use {layer.compress(Bitmap.CompressFormat.PNG,100,it)}
                                    val composed=Bitmap.createBitmap(vw,vh,Bitmap.Config.ARGB_8888);val canvas=Canvas(composed)
                                    background.draw(canvas);canvas.drawBitmap(layer,0f,0f,null);arms.draw(canvas)
                                    File(filesDir,"appearance-${if(baseline)"before" else "after"}-$index.png").outputStream().use {composed.compress(Bitmap.CompressFormat.PNG,100,it)}
                                    composed.recycle();layer.recycle()
                                }
                                background.setImageDrawable(null);arms.update(null);frame.recycle();mask?.recycle();latch.countDown()
                            },1200)
                        }
                        check(latch.await(8,TimeUnit.SECONDS))
                    }
                } }
            }catch(e:Exception){report.appendLine("ERROR ${e.javaClass.simpleName}: ${e.message}")}
            report.appendLine("Recording may already contain the old dress. Inspect isolated layers; replay composites do not establish naturalness or live accuracy.")
            report.appendLine("Finished ${System.currentTimeMillis()}")
            File(filesDir,"appearance-result-${if(baseline)"before" else "after"}.txt").writeText(report.toString())
            runOnUiThread { if(!isDestroyed)label.text=report.toString() }
        }
    }
    override fun onResume(){super.onResume();running=true;Choreographer.getInstance().postFrameCallback(this)}
    override fun onPause(){running=false;Choreographer.getInstance().removeFrameCallback(this);super.onPause()}
    override fun doFrame(time:Long){if(running){renderer?.render(time);Choreographer.getInstance().postFrameCallback(this)}}
    override fun onDestroy(){running=false;handler.removeCallbacksAndMessages(null);renderer?.close();worker.shutdown();super.onDestroy()}
}
