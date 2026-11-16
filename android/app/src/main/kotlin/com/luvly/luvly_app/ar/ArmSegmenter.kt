package com.luvly.luvly_app.ar

import android.content.Context
import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import java.nio.ByteOrder

/** Worker-thread owned local refinement. Slow devices refine only the frozen preview. */
class ArmSegmenter(context: Context): AutoCloseable {
    private var segmenter: ImageSegmenter?=null
    private val liveBudget=LiveRefinementBudget()
    var lastInferenceMs=0L
        private set
    var lastMode="none"
        private set
    val available: Boolean get()=segmenter!=null
    var backend="unavailable"
        private set
    var liveEnabled=true
        private set

    init {
        fun create(delegate: Delegate)=ImageSegmenter.createFromOptions(context,
                ImageSegmenter.ImageSegmenterOptions.builder()
                    .setBaseOptions(BaseOptions.builder()
                        .setModelAssetPath("selfie_multiclass_256x256.tflite")
                        .setDelegate(delegate).build())
                    .setRunningMode(RunningMode.IMAGE)
                    .setOutputCategoryMask(false).setOutputConfidenceMasks(true).build())
        try {
            segmenter=create(Delegate.GPU);backend="GPU"
        } catch(e: Exception) {
            Log.i("LuvlyAR","GPU segmentation unsupported; checking bounded CPU refinement")
            // CPU is deliberately preview-only: do not spend several live frames benchmarking it.
            try { segmenter=create(Delegate.CPU);backend="CPU";liveEnabled=false }
            catch(cpuError: Exception) {
                Log.w("LuvlyAR","Arm refinement unavailable; using basic pose preview",cpuError)
            }
        }
    }

    fun mask(frame: Bitmap,points: List<BodyPoint>, live: Boolean=true,processingBeforeMaskMs: Long=0): Bitmap? {
        lastInferenceMs=0
        lastMode="none"
        if(live && (!liveEnabled || segmenter==null))return fastMask(frame,points)
        val model=segmenter ?: return fastMask(frame,points)
        if(ArmOcclusion.capsules(points,frame.width,frame.height,skinIntersection=true).isEmpty())return null
        val start=SystemClock.uptimeMillis()
        val ratio=256f/maxOf(frame.width,frame.height)
        val small=Bitmap.createScaledBitmap(frame,(frame.width*ratio).toInt().coerceAtLeast(1),
            (frame.height*ratio).toInt().coerceAtLeast(1),true)
        val input=BitmapImageBuilder(small).build()
        try {
            val result=model.segment(input)
            val masks=result.confidenceMasks().orElse(emptyList())
            try {
                // Official SelfieMulticlass labels: 2 = body skin (not face, clothes or background).
                val skin=masks.getOrNull(2) ?: return null
                val buffer=ByteBufferExtractor.extract(skin).order(ByteOrder.nativeOrder()).asFloatBuffer()
                val values=FloatArray(skin.width*skin.height)
                buffer.get(values)
                val pixels=ArmSkinMask.pixels(SkinConfidence(skin.width,skin.height,values),
                    points,frame.width,frame.height) ?: return null
                lastMode="${backend}-semantic"
                return Bitmap.createBitmap(pixels,skin.width,skin.height,Bitmap.Config.ARGB_8888)
            } finally { masks.forEach { it.close() } }
        } catch(e: Exception) {
            Log.w("LuvlyAR","Arm segmentation interrupted; preserving basic preview",e)
            close();return null
        } finally {
            input.close()
            if(small!==frame && !small.isRecycled)small.recycle()
            lastInferenceMs=SystemClock.uptimeMillis()-start
            if(live) {
                liveBudget.observe(processingBeforeMaskMs,lastInferenceMs)
                if(!liveBudget.enabled) {
                    Log.i("LuvlyAR","Using frozen-preview-only arm refinement to preserve live speed")
                    liveEnabled=false
                }
            }
        }
    }

    private fun fastMask(frame: Bitmap,points: List<BodyPoint>): Bitmap? {
        if(ArmOcclusion.capsules(points,frame.width,frame.height,skinIntersection=true).isEmpty())return null
        val start=SystemClock.uptimeMillis()
        val scale=320f/maxOf(frame.width,frame.height)
        val small=Bitmap.createScaledBitmap(frame,(frame.width*scale).toInt().coerceAtLeast(1),
            (frame.height*scale).toInt().coerceAtLeast(1),true)
        return try {
            val rgb=IntArray(small.width*small.height);small.getPixels(rgb,0,small.width,0,0,small.width,small.height)
            val mask=FastArmMask.pixels(rgb,small.width,small.height,points,frame.width,frame.height) ?: return null
            lastMode="CPU-colour-matte"
            Bitmap.createBitmap(mask,small.width,small.height,Bitmap.Config.ARGB_8888)
        } finally {
            if(small!==frame)small.recycle()
            lastInferenceMs=SystemClock.uptimeMillis()-start
        }
    }

    override fun close() { segmenter?.close();segmenter=null }
}
