package com.luvly.luvly_app.ar

import android.graphics.*
import android.os.*
import android.view.PixelCopy
import java.io.File
import java.util.concurrent.Executors
import kotlin.math.*

/** Known camera/world correspondences. No real camera, account, or saved-look writes. */
class SpatialRegistrationFixtureActivity: TryOnActivity() {
    private val handler=Handler(Looper.getMainLooper())
    private val writer=Executors.newSingleThreadExecutor()
    private var alive=true
    private val samples=linkedMapOf<String,MutableList<SpatialDressPose?>>()
    private val captured=mutableSetOf<String>()
    private val tiltSamples=linkedMapOf<String,MutableList<Float?>>()
    private data class Stage(val name: String,val yaw: Float,val depth: Float,val offset: Float=0f,val lost: Boolean=false,val offsetY: Float=0f,val pitch: Float=0f,val rejected: Boolean=false,val shoulderLift: Float=0f)
    private val stages=listOf(Stage("front",0f,2.5f),Stage("turn-left",-35f,2.5f),
        Stage("turn-right",35f,2.5f),Stage("near",0f,2f),Stage("far",0f,3.2f),
        Stage("move-right",0f,2.5f,.22f),Stage("world-lost",0f,2.5f,lost=true),Stage("recovered",0f,2.5f),
        Stage("low-frame",0f,2.5f,offsetY=-1.05f),Stage("low-turn",25f,2.5f,offsetY=-1.05f),
        Stage("low-pitch",0f,2.5f,offsetY=-1.05f,pitch=20f),
        Stage("profile-front",0f,2.5f),Stage("profile-45",45f,2.5f),
        Stage("profile-70",70f,2.5f),Stage("profile-90",90f,2.5f),
        Stage("profile-90-near",90f,2f),Stage("profile-return",0f,2.5f),
        Stage("profile-minus45",-45f,2.5f),Stage("profile-minus70",-70f,2.5f),
        Stage("profile-minus90",-90f,2.5f),Stage("back-rejected",-120f,2.5f,rejected=true),
        Stage("profile-recovered",0f,2.5f),Stage("shoulder-left-up",0f,2.5f,shoulderLift=.03f),
        Stage("shoulder-right-up",0f,2.5f,shoulderLift=-.03f),Stage("shoulders-level",0f,2.5f))
    private lateinit var model: ArDress
    override fun onCreate(savedInstanceState: Bundle?) {
        model=ArDressCatalogue.byId(intent.getStringExtra("fixtureDress")) ?: ArDressCatalogue.byId("elegant-local-review")!!
        intent.putExtra("dressId",model.id);intent.putExtra("modelAsset",model.asset)
        super.onCreate(savedInstanceState)
        if(intent.getBooleanExtra("fixtureDiagnostics",false))showTrackingDiagnostics()
    }
    override fun beginCameraExperience() {
        val frame=FrameProjection(600,900,800f,800f,source="synthetic-known-lens")
        val camera=frame.forView(600,900)!!
        val source=MutableList(33){Vec3(0f,0f,0f)}.apply {
            this[0]=Vec3(0f,.75f,0f)
            this[11]=Vec3(-.2f,.52f,0f);this[12]=Vec3(.2f,.52f,0f)
            this[23]=Vec3(-.14f,0f,0f);this[24]=Vec3(.14f,0f,0f)
            this[13]=Vec3(-.3f,.20f,0f);this[14]=Vec3(.3f,.20f,0f)
            this[15]=Vec3(-.32f,-.15f,0f);this[16]=Vec3(.32f,-.15f,0f)
            for(i in listOf(27,28,31,32))this[i]=Vec3(if(i%2==0).1f else -.1f,-.9f,0f)
        }
        val inputs=stages.map { stage->
            val yaw=Math.toRadians(stage.yaw.toDouble()).toFloat()
            val pitch=Math.toRadians(stage.pitch.toDouble()).toFloat()
            val world=source.mapIndexed { i,original->
                val it=original+Vec3(0f,when(i) { 11 -> stage.shoulderLift;12 -> -stage.shoulderLift;else -> 0f },0f)
                val y=it.y*cos(pitch)-it.z*sin(pitch);val z=it.y*sin(pitch)+it.z*cos(pitch)
                Vec3(it.x*cos(yaw)+z*sin(yaw),y,-it.x*sin(yaw)+z*cos(yaw))
            }
            val pixels=world.map { camera.project(it+Vec3(stage.offset,stage.offsetY,-stage.depth))!! }
            val image=pixels.map { BodyPoint(it.first/600,1-it.second/900,1f) }
            val bitmap=Bitmap.createBitmap(600,900,Bitmap.Config.ARGB_8888)
            val canvas=Canvas(bitmap);canvas.drawColor(Color.rgb(226,230,232))
            val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.rgb(55,125,132);strokeCap=Paint.Cap.ROUND }
            fun point(i: Int)=PointF(pixels[i].first,900-pixels[i].second)
            val head=point(0);canvas.drawCircle(head.x,head.y,800*.09f/stage.depth,paint)
            val path=Path()
            for((j,i) in listOf(11,12,24,23).withIndex()) {
                val p=point(i);if(j==0)path.moveTo(p.x,p.y) else path.lineTo(p.x,p.y)
            }
            path.close();canvas.drawPath(path,paint)
            paint.strokeWidth=800*.05f/stage.depth
            for((a,b) in listOf(11 to 13,13 to 15,12 to 14,14 to 16,23 to 31,24 to 32)) {
                val p=point(a);val q=point(b);canvas.drawLine(p.x,p.y,q.x,q.y,paint)
            }
            paint.color=Color.DKGRAY;paint.textSize=18f
            canvas.drawText("Synthetic 3D registration: ${stage.name}",45f,35f,paint)
            Triple(bitmap,image,world.map { WorldBodyPoint(it.x,-it.y,-it.z,1f) })
        }
        var started=0L
        handler.post(object: Runnable {
            override fun run() {
                if(!alive)return
                if(!window.decorView.hasWindowFocus()) { handler.postDelayed(this,150);return }
                val now=SystemClock.uptimeMillis();if(started==0L)started=now
                val elapsed=now-started;val index=(elapsed/3000).toInt()
                if(index>=stages.size) { report();return }
                val stage=stages[index];val data=inputs[index]
                // Includes inference age, through the same path as live detection.
                displayCameraFrame(data.first,data.second,now-200,world=if(stage.lost)emptyList() else data.third,projection=frame)
                if(elapsed%3000 in 1700..2600) {
                    samples.getOrPut(stage.name){mutableListOf()}.add(spatialPoseProbe())
                    tiltSamples.getOrPut(stage.name){mutableListOf()}.add(shoulderTiltProbe())
                    if(captured.add(stage.name))capture("ar_spatial_${stage.name}.png")
                }
                handler.postDelayed(this,100)
            }
        })
    }
    private fun report() {
        val result=buildString {
            appendLine("Completed: ${System.currentTimeMillis()}")
            appendLine("Synthetic camera/world pairs; not real-person accuracy; no camera or albums")
            for(stage in stages) {
                val values=samples[stage.name].orEmpty()
                val pass=values.size>=4 && values.all { p->
                    if(stage.lost || stage.rejected)p==null else p!=null && abs(p.yawDegrees-stage.yaw)<2f &&
                        abs(p.shoulder.z+stage.depth-.52f*sin(Math.toRadians(stage.pitch.toDouble()).toFloat()))<.05f && abs(p.shoulder.x-stage.offset)<.03f &&
                        abs(p.widthScale-.4f/model.anchors.shoulderWidth)<.02f && p.errorPixels<1f
                }
                val tilts=tiltSamples[stage.name].orEmpty()
                val tiltPass=!model.anchors.adaptiveFit || when {
                    stage.lost || stage.rejected -> true
                    stage.shoulderLift!=0f -> tilts.size>=4 && tilts.all { it!=null && it*stage.shoulderLift<-.004f }
                    else -> tilts.size>=4 && tilts.all { it!=null && abs(it)<.18f }
                }
                appendLine("${if(pass && tiltPass)"PASS" else "FAIL"} ${stage.name}: samples=${values.size}; yaw=${values.lastOrNull()?.yawDegrees}; depth=${values.lastOrNull()?.shoulder?.z}; tilt=${tilts.lastOrNull()}")
            }
        }
        val trace=trackingTraceProbe()
        writer.execute {
            File(filesDir,"ar_spatial_result.txt").writeText(result)
            // Debug fixture's synthetic values only; live traces require explicit export.
            File(filesDir,"ar_spatial_trace.csv").writeText(trace)
        }
        if(intent.getBooleanExtra("fixtureTraceExport",false)) {
            exportTrackingTrace() // Inspect confirmation only; never chooses a file destination.
            handler.postDelayed({ capture("ar_trace_export_dialog.png") },600)
        }
    }
    private fun capture(name: String) {
        val view=window.decorView
        val bitmap=Bitmap.createBitmap(view.width,view.height,Bitmap.Config.ARGB_8888)
        PixelCopy.request(window,bitmap,{ result->
            writer.execute {
                try { if(result==PixelCopy.SUCCESS)File(filesDir,name).outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG,100,it)
                } } finally { bitmap.recycle() }
            }
        },handler)
    }
    override fun onDestroy() {
        alive=false;handler.removeCallbacksAndMessages(null);writer.shutdown();super.onDestroy()
    }
}
