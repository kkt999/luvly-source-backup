package com.luvly.luvly_app.ar

import android.graphics.*
import android.os.*
import android.view.PixelCopy
import java.io.File
import java.util.concurrent.Executors

/** No camera, account, or album writes. Exercise real UI/render ticks through tracking gaps. */
class TrackingStabilityFixtureActivity: TryOnActivity() {
    private val handler=Handler(Looper.getMainLooper())
    private val evidenceWriter=Executors.newSingleThreadExecutor()
    private var alive=true
    private val samples=mutableMapOf<String,MutableList<Triple<Boolean,Float,Boolean>>>()
    private val captures=mutableSetOf<String>()
    override fun onCreate(state: Bundle?) {
        val model=ArDressCatalogue.byId("elegant-local-review")!!
        intent.putExtra("dressId",model.id);intent.putExtra("modelAsset",model.asset)
        super.onCreate(state)
    }

    override fun beginCameraExperience() {
        val bitmap=Bitmap.createBitmap(600,900,Bitmap.Config.ARGB_8888)
        val canvas=Canvas(bitmap);canvas.drawColor(Color.rgb(226,230,232))
        val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.rgb(55,125,132) }
        canvas.drawOval(258f,65f,342f,175f,paint)
        canvas.drawRect(278f,155f,322f,225f,paint)
        canvas.drawRoundRect(180f,215f,420f,485f,25f,25f,paint)
        paint.strokeWidth=40f;paint.strokeCap=Paint.Cap.ROUND
        canvas.drawLine(180f,245f,150f,590f,paint);canvas.drawLine(420f,245f,450f,590f,paint)
        canvas.drawLine(250f,460f,250f,845f,paint);canvas.drawLine(350f,460f,350f,845f,paint)
        paint.color=Color.DKGRAY;paint.textSize=17f
        canvas.drawText("Synthetic tracking-loss test · no camera",95f,35f,paint)
        val body=MutableList(33){BodyPoint(.5f,.5f,1f)}.apply {
            this[0]=BodyPoint(.5f,.13f,1f)
            this[11]=BodyPoint(.3f,.25f,1f);this[12]=BodyPoint(.7f,.25f,1f)
            this[23]=BodyPoint(.4f,.50f,1f);this[24]=BodyPoint(.6f,.50f,1f)
            for(i in listOf(27,28,31,32))this[i]=BodyPoint(if(i%2==0).58f else .42f,.94f,1f)
        }
        val weak=body.map { it.copy(confidence=.35f) }
        val projection=FrameProjection(600,900,900f,900f,source="synthetic-known-lens")
        val world=body.map { WorldBodyPoint((it.x-.5f)*600*1.5f/900,(it.y-.5f)*1.5f,0f,1f) }
        var started=0L
        var lastInput=0L
        handler.post(object: Runnable {
            override fun run() {
                if(!alive)return
                if(!window.decorView.hasWindowFocus() || window.decorView.width<=0) {
                    handler.postDelayed(this,200);return
                }
                val now=SystemClock.uptimeMillis()
                if(started==0L)started=now
                val elapsed=now-started
                val noFrames=elapsed in 8500..10499
                if(!noFrames && now-lastInput>=95) {
                    lastInput=now
                    val points=when(elapsed) {
                        in 2500..2999, in 12000..13999 -> emptyList()
                        in 4500..4999 -> weak
                        else -> body
                    }
                    // Simulate 450 ms inference delay too. Grace must use delivery,
                    // but photo readiness must still use this older input timestamp.
                    displayCameraFrame(bitmap,points,now-450,world=world,projection=projection)
                }
                val phase=when(elapsed) {
                    in 2650..2950 -> "short-missing"
                    in 4650..4950 -> "short-weak"
                    in 8750..8950 -> "stall-grace"
                    in 9200..9350 -> "stall-fade"
                    in 9750..10250 -> "stall-hidden"
                    in 11300..11600 -> "recovered"
                    in 13250..13750 -> "missing-hidden"
                    else -> null
                }
                if(phase!=null) {
                    val probe=trackingDisplayProbe()
                    samples.getOrPut(phase){mutableListOf()}.add(probe)
                    if(phase in listOf("short-missing","stall-fade","stall-hidden","recovered") && captures.add(phase))
                        capture("ar_stability_$phase.png")
                }
                if(elapsed>=15500) { finishReport();return }
                handler.postDelayed(this,50)
            }
        })
    }

    private fun finishReport() {
        val checks=linkedMapOf<String,Boolean>()
        for(name in listOf("short-missing","short-weak","stall-grace")) {
            val values=samples[name].orEmpty()
            checks[name]=values.size>=3 && values.all { it.first && it.second>=.99f }
        }
        for(name in listOf("short-missing","short-weak","stall-grace","stall-fade","stall-hidden","missing-hidden"))
            checks["$name-no-capture"]=samples[name].orEmpty().let { it.isNotEmpty() && it.none { p->p.third } }
        checks["bounded-fade"]=samples["stall-fade"].orEmpty().any { it.first && it.second in .01f.. .95f }
        for(name in listOf("stall-hidden","missing-hidden"))
            checks[name]=samples[name].orEmpty().let { it.size>=3 && it.none { p->p.first || p.second>.001f } }
        checks["recovered"]=samples["recovered"].orEmpty().let {
            it.size>=3 && it.all { p->p.first && p.second>=.99f && p.third }
        }
        val report=buildString {
            appendLine("Completed: ${System.currentTimeMillis()}")
            appendLine("Synthetic only; detector input age 450 ms; no camera or album writes")
            checks.forEach { (name,pass)->appendLine("${if(pass)"PASS" else "FAIL"} $name") }
            samples.forEach { (name,values)->appendLine("$name samples=${values.size} minAlpha=${values.minOfOrNull { it.second }} maxAlpha=${values.maxOfOrNull { it.second }}") }
        }
        // Queue behind screenshots so the host cannot read half-written evidence.
        evidenceWriter.execute { File(filesDir,"ar_stability_result.txt").writeText(report) }
    }

    private fun capture(name: String) {
        val view=window.decorView
        val snapshot=Bitmap.createBitmap(view.width,view.height,Bitmap.Config.ARGB_8888)
        PixelCopy.request(window,snapshot,{ result->
            // Full-screen PNG compression can take >1 s on this phone. Doing it
            // on the UI thread would introduce the very stalls being measured.
            evidenceWriter.execute {
                try {
                    if(result==PixelCopy.SUCCESS)File(filesDir,name).outputStream().use {
                        snapshot.compress(Bitmap.CompressFormat.PNG,100,it)
                    }
                } finally { snapshot.recycle() }
            }
        },handler)
    }

    override fun onDestroy() {
        alive=false;handler.removeCallbacksAndMessages(null);evidenceWriter.shutdown();super.onDestroy()
    }
}
