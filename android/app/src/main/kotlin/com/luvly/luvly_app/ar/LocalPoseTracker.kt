package com.luvly.luvly_app.ar

import android.content.Context
import android.util.Log
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult

/** Create, detect and close on the same worker (GPU context ownership).
 * Two people remain enabled for target continuity / reflection rejection.
 * A failed GPU inference is discarded; CPU resumes on the NEXT fresh frame.
 */
internal class LocalPoseTracker(private val context: Context, preferGpu: Boolean=false,
                                private val silhouette: Boolean=false): AutoCloseable {
    private val owner=Thread.currentThread()
    private var model: PoseLandmarker
    var backend="CPU"
        private set
    val modelName="full"
    init {
        model=if(preferGpu)try {
            create(Delegate.GPU).also { backend="GPU" }
        } catch(_:Exception) {
            Log.i("LuvlyAR","GPU pose unavailable; using CPU")
            create(Delegate.CPU)
        } else create(Delegate.CPU)
    }
    private fun create(delegate: Delegate)=PoseLandmarker.createFromOptions(context,
        PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("pose_landmarker_full.task")
                .setDelegate(delegate).build())
            .setRunningMode(RunningMode.VIDEO).setNumPoses(2)
            .setMinPoseDetectionConfidence(.6f).setMinPosePresenceConfidence(.6f)
            .setMinTrackingConfidence(.6f).setOutputSegmentationMasks(silhouette).build())
    fun detect(input: MPImage, timestamp: Long): PoseLandmarkerResult? {
        check(Thread.currentThread()===owner)
        return try { model.detectForVideo(input,timestamp) } catch(e:Exception) {
            if(backend!="GPU")throw e
            runCatching { model.close() }
            model=create(Delegate.CPU);backend="CPU"
            Log.i("LuvlyAR","GPU pose interrupted; CPU will resume with fresh input")
            null
        }
    }
    override fun close() { check(Thread.currentThread()===owner);model.close() }
}
