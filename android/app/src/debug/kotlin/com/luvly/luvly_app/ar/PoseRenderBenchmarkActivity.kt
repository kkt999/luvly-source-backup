package com.luvly.luvly_app.ar

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.SystemClock
import com.google.mediapipe.framework.image.BitmapImageBuilder
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Compare delegates with the production Filament view rendering concurrently.
 * Local recorded inputs only. No camera, saved looks or uploads. Not accuracy QA.
 */
class PoseRenderBenchmarkActivity: TryOnActivity() {
    private val replay=Executors.newSingleThreadExecutor()
    @Volatile private var stopped=false
    override fun onCreate(savedInstanceState: Bundle?) {
        val dress=ArDressCatalogue.byId("princess-wedding")!!
        intent.putExtra("dressId",dress.id);intent.putExtra("modelAsset",dress.asset)
        super.onCreate(savedInstanceState)
    }
    override fun beginCameraExperience() {
        replay.execute {
            val inputs=File(filesDir,"ar_benchmark_input").listFiles()?.filter { it.name.matches(Regex("frame-[0-9]+\\.jpg")) }?.sortedBy { it.name } ?: emptyList()
            val report=StringBuilder("Started: ${System.currentTimeMillis()}\nRecorded frames with Filament: ${inputs.size}\n")
            try {
                check(inputs.size>=5)
                val frames=inputs.map { checkNotNull(BitmapFactory.decodeFile(it.absolutePath)) }
                try {
                    for(gpu in listOf(false,true,true,false)) {
                        if(stopped)break
                        val lock=BodyTargetLock()
                        LocalPoseTracker(this,gpu).use { tracker ->
                            val inferenceMs=mutableListOf<Long>();val combinedMs=mutableListOf<Long>()
                            var shown=0
                            repeat(3) { pass -> frames.forEach { source ->
                                if(stopped)return@forEach
                                val start=SystemClock.uptimeMillis()
                                val bitmap=source.copy(Bitmap.Config.ARGB_8888,false)
                                val inference=source.copy(Bitmap.Config.ARGB_8888,false)
                                val input=BitmapImageBuilder(inference).build()
                                val poseStart=SystemClock.uptimeMillis()
                                val result=try { tracker.detect(input,start) } finally { input.close();if(!inference.isRecycled)inference.recycle() }
                                val poseEnd=SystemClock.uptimeMillis()
                                val people=result?.landmarks()?.map { person->person.map {
                                    BodyPoint(it.x(),it.y(),minOf(it.visibility().orElse(0f),it.presence().orElse(0f)),it.z())
                                } } ?: emptyList()
                                val selected=lock.select(people,bitmap.width,bitmap.height,start)
                                val points=selected.index?.let { people[it] } ?: emptyList()
                                val world=selected.index?.let { result?.worldLandmarks()?.getOrNull(it) }?.map {
                                    WorldBodyPoint(it.x(),it.y(),it.z(),it.visibility().orElse(0f))
                                } ?: emptyList()
                                val done=CountDownLatch(1)
                                runOnUiThread {
                                    try {
                                        if(stopped)bitmap.recycle() else {
                                            displayCameraFrame(bitmap,points,start,world=world,
                                                projection=FrameProjection.estimated(bitmap.width,bitmap.height),
                                                targetReason=selected.reason,resetAlignment=selected.resetAlignment,
                                                retainCalibration=selected.retainCalibration)
                                            if(trackingDisplayProbe().first)shown++
                                        }
                                    } finally { done.countDown() }
                                }
                                check(done.await(3,TimeUnit.SECONDS)) { "UI did not complete replay frame" }
                                if(pass>0) { inferenceMs.add(poseEnd-poseStart);combinedMs.add(SystemClock.uptimeMillis()-start) }
                            } }
                            fun stats(v:List<Long>):String {
                                val s=v.sorted();return if(s.isEmpty())"none" else "median=${s[s.size/2]} p95=${s[((s.size-1)*.95).toInt()]}"
                            }
                            report.append("preferGpu=$gpu backend=${tracker.backend} n=${inferenceMs.size} poseMs ${stats(inferenceMs)} processedAndUiMs ${stats(combinedMs)} visibleFrames=$shown/30\n")
                            File(filesDir,"ar_pose_render_benchmark.txt").writeText(report.toString())
                        }
                    }
                } finally { frames.forEach { if(!it.isRecycled)it.recycle() } }
            } catch(e:Exception) { report.append("ERROR ${e.javaClass.simpleName}: ${e.message}\n") }
            finally { inputs.forEach { it.delete() } }
            report.append("Finished: ${System.currentTimeMillis()}\nRecorded replay excludes camera acquisition/rotation and recording overhead. Not live FPS or fit accuracy.\n")
            File(filesDir,"ar_pose_render_benchmark.txt").writeText(report.toString())
        }
    }
    override fun onDestroy() { stopped=true;replay.shutdown();super.onDestroy() }
}
