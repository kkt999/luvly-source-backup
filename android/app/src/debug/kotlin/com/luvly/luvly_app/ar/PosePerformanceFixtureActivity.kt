package com.luvly.luvly_app.ar

import android.app.Activity
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.SystemClock
import android.widget.TextView
import com.google.mediapipe.framework.image.BitmapImageBuilder
import java.io.File
import java.util.concurrent.Executors

/** Debug only, camera-free replay. Inputs supplied locally, never bundled/uploaded.
 * Deletes temporary input images after testing. Durations are inference-only.
 */
class PosePerformanceFixtureActivity: Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val label=TextView(this).apply { text="Checking pose inference on supplied recorded frames. Camera stays off." }
        setContentView(label)
        val worker=Executors.newSingleThreadExecutor()
        worker.execute {
            val inputs=File(filesDir,"ar_benchmark_input").listFiles()?.filter { it.name.matches(Regex("frame-[0-9]+\\.jpg")) }?.sortedBy { it.name } ?: emptyList()
            val report=StringBuilder("Completed: ${System.currentTimeMillis()}\nRecorded frames: ${inputs.size}\n")
            try {
                check(inputs.size>=5) { "Supply at least five local recorded input frames" }
                val frames=inputs.map { checkNotNull(BitmapFactory.decodeFile(it.absolutePath)) }
                try {
                    // Repeat order to expose first-run/warm-up and thermal effects.
                    for(preferGpu in listOf(false,true,true,false)) {
                        runCatching {
                            LocalPoseTracker(this,preferGpu).use { tracker ->
                                val times=mutableListOf<Long>();var bodies=0;var pairs=0;var restarts=0
                                repeat(3) { pass -> frames.forEachIndexed { i,bitmap ->
                                    // MPImage owns its bitmap container. Each inference
                                    // needs a fresh copy; closing must not recycle a
                                    // source bitmap needed by the next replay pass.
                                    val copy=bitmap.copy(android.graphics.Bitmap.Config.ARGB_8888,false)
                                    val input=BitmapImageBuilder(copy).build()
                                    val start=SystemClock.uptimeMillis()
                                    val result=try { tracker.detect(input,1000L+(pass*frames.size+i)*200L) } finally {
                                        input.close();if(!copy.isRecycled)copy.recycle()
                                    }
                                    if(pass>0) {
                                        times.add(SystemClock.uptimeMillis()-start)
                                        if(result==null)restarts++ else {
                                            if(result.landmarks().isNotEmpty())bodies++
                                            if(result.landmarks().size==result.worldLandmarks().size)pairs++
                                        }
                                    }
                                } }
                                val sorted=times.sorted()
                                report.append("model=${tracker.modelName} preferGpu=$preferGpu backend=${tracker.backend} measured=${times.size} medianMs=${sorted[sorted.size/2]} p95Ms=${sorted[((sorted.size-1)*.95).toInt()]} bodies=$bodies paired=$pairs restarts=$restarts samples=$times\n")
                            }
                        }.onFailure { report.append("ERROR preferGpu=$preferGpu: ${it.javaClass.simpleName}: ${it.message}\n") }
                    }
                } finally { frames.forEach { it.recycle() } }
            } catch(e:Exception) { report.append("ERROR: ${e.message}\n") }
            finally { inputs.forEach { it.delete() } }
            report.append("Inference-only replay; not live camera FPS or tracking accuracy.\nFinished: ${System.currentTimeMillis()}\n")
            File(filesDir,"ar_pose_performance.txt").writeText(report.toString())
            runOnUiThread { if(!isDestroyed)label.text=report.toString() }
            worker.shutdown()
        }
    }
}
