package com.luvly.luvly_app.ar

import android.app.Activity
import android.graphics.*
import android.os.Bundle
import android.widget.TextView
import java.io.File
import java.util.concurrent.Executors

/** Device delegate/performance smoke test; no camera and no personal image input. */
class ArmSegmenterFixtureActivity: Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val label=TextView(this).apply { text="Checking local arm model with a synthetic image…" }
        setContentView(label)
        val worker=Executors.newSingleThreadExecutor()
        worker.execute {
            val result=runCatching {
                val frame=Bitmap.createBitmap(600,900,Bitmap.Config.ARGB_8888)
                val canvas=Canvas(frame);canvas.drawColor(Color.LTGRAY)
                val paint=Paint().apply { color=Color.rgb(190,135,110) }
                canvas.drawOval(245f,60f,355f,190f,paint)
                canvas.drawRect(180f,225f,420f,600f,paint)
                val points=MutableList(33){BodyPoint(.5f,.5f,0f)}
                points[11]=BodyPoint(.3f,.25f,1f,0f);points[12]=BodyPoint(.7f,.25f,1f,0f)
                points[23]=BodyPoint(.4f,.6f,1f,0f);points[24]=BodyPoint(.6f,.6f,1f,0f)
                points[13]=BodyPoint(.32f,.5f,1f,-.15f);points[15]=BodyPoint(.52f,.48f,1f,-.2f)
                ArmSegmenter(this).use { segmenter ->
                    val initial=segmenter.available
                    val times=mutableListOf<Long>()
                    var returned=0
                    repeat(10) {
                        segmenter.mask(frame,points)?.let { returned++;it.recycle() }
                        times.add(segmenter.lastInferenceMs)
                    }
                    val live=segmenter.liveEnabled
                    val frozenMask=segmenter.mask(frame,points,live=false)
                    val frozenWorked=frozenMask!=null;frozenMask?.recycle()
                    val frozenMs=segmenter.lastInferenceMs
                    frame.recycle()
                    "Completed: ${System.currentTimeMillis()}\nModel available: $initial\nBackend: ${segmenter.backend}\nMasks returned: $returned\nInference ms: $times\nLive refinement: $live\nFrozen refinement: $frozenWorked\nFrozen inference ms: $frozenMs\nSynthetic input: not accuracy evidence\n"
                }
            }.getOrElse { "ERROR: ${it.stackTraceToString()}" }
            File(filesDir,"ar_segmenter_result.txt").writeText(result)
            runOnUiThread { if(!isDestroyed)label.text=result }
            worker.shutdown()
        }
    }
}
