package com.luvly.luvly_app.ar

import android.app.Activity
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.SystemClock
import android.widget.TextView
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/** Debug-only local screen-recording probe. No camera/network/business records.
 * Coarse central torso detection is not registration accuracy or identity. */
class ProfileModelProbeActivity: Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val label=TextView(this).apply { text="Comparing local pose models. Camera stays off.";textSize=16f }
        setContentView(label)
        val worker=Executors.newSingleThreadExecutor()
        worker.execute {
            val dir=File(filesDir,"ar_profile_probe")
            val inputs=dir.listFiles()?.filter { it.name.matches(Regex("frame-[0-9]+\\.jpg")) }?.sortedBy { it.name }.orEmpty()
            val full=File(dir,"pose_landmarker_full.task")
            val report=StringBuilder("Started: ${System.currentTimeMillis()}\nInput frames=${inputs.size}\n")
            try {
                check(inputs.size==14 && full.isFile)
                for(model in listOf("lite","full"))for(threshold in listOf(.6f,.5f)) {
                    for(pass in 0..1) {
                        val timings=mutableListOf<Long>();var central=0;var any=0;val observations=mutableListOf<String>()
                        // Reset at each independent clip, as a detector-reacquisition probe.
                        for(segment in listOf(inputs.take(8),inputs.drop(8))) {
                            val base=BaseOptions.builder().setDelegate(Delegate.CPU)
                            if(model=="lite")base.setModelAssetPath("pose_landmarker_lite.task")
                            else {
                                val bytes=full.readBytes();val buffer=ByteBuffer.allocateDirect(bytes.size)
                                buffer.put(bytes);buffer.rewind();base.setModelAssetBuffer(buffer)
                            }
                            val options=PoseLandmarker.PoseLandmarkerOptions.builder().setBaseOptions(base.build())
                                .setRunningMode(RunningMode.VIDEO).setNumPoses(2)
                                .setMinPoseDetectionConfidence(threshold).setMinPosePresenceConfidence(threshold)
                                .setMinTrackingConfidence(threshold).build()
                            PoseLandmarker.createFromOptions(this,options).use { detector ->
                                segment.forEachIndexed { i,file ->
                                    val bitmap=checkNotNull(BitmapFactory.decodeFile(file.absolutePath))
                                    val input=BitmapImageBuilder(bitmap).build();val started=SystemClock.uptimeMillis()
                                    val result=try { detector.detectForVideo(input,1000L+i*500L) }
                                        finally { input.close();if(!bitmap.isRecycled)bitmap.recycle() }
                                    timings.add(SystemClock.uptimeMillis()-started)
                                    val poses=result.landmarks()
                                    if(poses.isNotEmpty())any++
                                    val found=poses.any { p->
                                        val joints=listOf(11,12,23,24).map { p[it] }
                                        joints.all { minOf(it.visibility().orElse(0f),it.presence().orElse(0f))>=.45f } &&
                                            joints.map { it.x() }.average() in .40.. .80
                                    }
                                    if(found)central++
                                    observations.add("${file.name}:${poses.size}:${if(found)1 else 0}")
                                }
                            }
                        }
                        val sorted=timings.sorted()
                        report.appendLine("model=$model threshold=$threshold pass=$pass any=$any centralTorso=$central/14 medianMs=${sorted[sorted.size/2]} p95Ms=${sorted[((sorted.size-1)*.95).toInt()]} observations=$observations")
                        File(filesDir,"ar_profile_probe_result.txt").writeText(report.toString())
                    }
                }
                var wrapperCentral=0;var paired=0
                LocalPoseTracker(this).use { tracker->
                    inputs.forEachIndexed { i,file->
                        val bitmap=checkNotNull(BitmapFactory.decodeFile(file.absolutePath))
                        val image=BitmapImageBuilder(bitmap).build()
                        val result=try { tracker.detect(image,1000L+i*500L) }
                            finally { image.close();if(!bitmap.isRecycled)bitmap.recycle() }
                        if(result!=null) {
                            if(result.landmarks().isNotEmpty() && result.landmarks().size==result.worldLandmarks().size)paired++
                            if(result.landmarks().any { p->
                                val joints=listOf(11,12,23,24).map { p[it] }
                                joints.all { minOf(it.visibility().orElse(0f),it.presence().orElse(0f))>=.45f } &&
                                    joints.map { it.x() }.average() in .40.. .80
                            })wrapperCentral++
                        }
                    }
                    report.appendLine("Production wrapper: model=${tracker.modelName} backend=${tracker.backend} centralTorso=$wrapperCentral/14 nonemptyPaired=$paired/14")
                }
            } catch(e:Exception) { report.appendLine("ERROR ${e.javaClass.simpleName}: ${e.message}") }
            finally { inputs.forEach { it.delete() };full.delete();dir.delete() }
            report.appendLine("Finished: ${System.currentTimeMillis()}")
            report.appendLine("Recompressed recording frames, selected failure cases, coarse central-torso heuristic. Not live FPS or accuracy benchmark.")
            File(filesDir,"ar_profile_probe_result.txt").writeText(report.toString())
            runOnUiThread { if(!isDestroyed)label.text=report.toString() };worker.shutdown()
        }
    }
}
