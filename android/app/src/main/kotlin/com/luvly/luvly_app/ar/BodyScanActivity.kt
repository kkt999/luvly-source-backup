package com.luvly.luvly_app.ar

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.*
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import com.google.firebase.auth.FirebaseAuth
import com.luvly.luvly_app.BuildConfig
import com.google.mediapipe.framework.image.ByteBufferExtractor
import java.nio.ByteOrder
import java.util.concurrent.Executors
import kotlin.math.round

/** Separate camera session: no change to try-on rendering, no frame storage/upload.
 * Returns ratios to Flutter for explicit review; never writes a profile itself. */
class BodyScanActivity: ComponentActivity() {
    private val worker=Executors.newSingleThreadExecutor()
    private val scan=BodyProportionScan()
    private val girth by lazy {
        intent.getDoubleExtra("heightCm",Double.NaN).takeIf { it in 120.0..220.0 }?.let(::BodyGirthScan)
    }
    private var tracker: LocalPoseTracker?=null // worker owns tracker and accumulator
    private var provider: ProcessCameraProvider?=null
    private lateinit var preview: ImageView
    private lateinit var guide: BodyScanGuideView
    private lateinit var status: TextView
    private lateinit var progress: ProgressBar
    private lateinit var retry: Button
    private lateinit var switch: Button
    private var displayed: Bitmap?=null
    private var owner: String?=null
    private var front=true
    private var permissionAsked=false
    @Volatile private var epoch=0
    @Volatile private var active=false
    @Volatile private var dead=false
    @Volatile private var posted=false
    @Volatile private var complete=false
    private var lastFrame=0L
    private var lastDiagnostic=0L
    private val permission=registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted->
        if(granted)bindCamera() else {status.text="Camera access was not allowed. You can still enter measurements manually.";retry.isEnabled=true}
    }
    private fun label(value: String,size: Float=15f)=TextView(this).apply {
        text=value;textSize=size;setTextColor(Color.rgb(54,43,47));setPadding(18,8,18,8)
    }
    private fun button(value: String,action: ()->Unit)=Button(this).apply {
        text=value;isAllCaps=false;setTextColor(Color.rgb(148,67,86));setOnClickListener{action()}
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        owner=FirebaseAuth.getInstance().currentUser?.uid
        if(owner==null){finish();return}
        // The customer can explicitly choose to screen-record a scan for help.
        // Luvly itself still never records, saves or uploads camera frames.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val root=LinearLayout(this).apply {orientation=LinearLayout.VERTICAL;setBackgroundColor(Color.rgb(253,249,246))}
        val header=LinearLayout(this).apply {gravity=Gravity.CENTER_VERTICAL}
        header.addView(button("Back"){finish()})
        header.addView(label(if(girth==null)"Scan proportions" else "Estimate body measurements",20f),
            LinearLayout.LayoutParams(0,-2,1f))
        root.addView(header)
        root.addView(label(if(girth==null)"Phone upright near chest height • Fit head to hips in the outline"
            else "Keep the phone fixed and upright at waist height • Frame your head and feet"))
        preview=ImageView(this).apply {scaleType=ImageView.ScaleType.FIT_CENTER;setBackgroundColor(Color.BLACK);contentDescription="Live camera preview; frames stay on this device"}
        guide=BodyScanGuideView(this,fullBody=girth!=null).apply{importantForAccessibility=android.view.View.IMPORTANT_FOR_ACCESSIBILITY_NO;isClickable=false}
        val cameraArea=FrameLayout(this)
        cameraArea.addView(preview,FrameLayout.LayoutParams(-1,-1))
        cameraArea.addView(guide,FrameLayout.LayoutParams(-1,-1))
        root.addView(cameraArea,LinearLayout.LayoutParams(-1,0,1f))
        progress=ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal).apply {max=100}
        root.addView(progress)
        // Scrollable guidance remains readable with large Android font settings.
        val guidance=ScrollView(this)
        status=label("Starting body tracking…")
        guidance.addView(status);root.addView(guidance,LinearLayout.LayoutParams(-1,(96*resources.displayMetrics.density).toInt()))
        val controls=LinearLayout(this)
        retry=button("Retry camera"){startCamera()}
        switch=button("Switch camera"){front=!front;bindCamera()}
        controls.addView(retry,LinearLayout.LayoutParams(0,-2,1f))
        controls.addView(switch,LinearLayout.LayoutParams(0,-2,1f))
        root.addView(controls)
        root.addView(label("Estimates only. Luvly does not save camera frames.",12f))
        setContentView(root)
    }
    override fun onResume(){super.onResume();if(owner==null)return;active=true
        if(!permissionAsked || ContextCompat.checkSelfPermission(this,Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)startCamera()
    }
    private fun startCamera(){
        if(dead || !active || complete)return
        if(ContextCompat.checkSelfPermission(this,Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)bindCamera()
        else {permissionAsked=true;permission.launch(Manifest.permission.CAMERA)}
    }
    private fun bindCamera(){
        if(!active || dead || complete)return
        if(ContextCompat.checkSelfPermission(this,Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){startCamera();return}
        val generation=++epoch
        progress.progress=0;retry.isEnabled=false;switch.isEnabled=false;status.text="Starting camera…"
        guide.updateFrame(480,640,false)
        worker.execute{scan.reset();girth?.reset();lastFrame=0;tracker?.close();tracker=null}
        val future=ProcessCameraProvider.getInstance(this)
        future.addListener({
            if(dead || !active || generation!=epoch)return@addListener
            try {
                val p=future.get();provider=p
                val hasFront=p.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
                val hasBack=p.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
                if(!hasFront && !hasBack)error("No camera")
                if(!hasFront)front=false else if(!hasBack)front=true
                val mirror=front
                val analysis=ImageAnalysis.Builder().setResolutionSelector(ResolutionSelector.Builder()
                    .setResolutionStrategy(ResolutionStrategy(android.util.Size(640,480),ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER)).build())
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888).build()
                p.unbindAll()
                p.bindToLifecycle(this,if(front)CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA,analysis)
                analysis.setAnalyzer(worker){frame->analyze(frame,mirror,generation)}
                switch.isEnabled=hasFront&&hasBack;retry.isEnabled=true
                status.text="Line up with the outline; keep mirrors out of view"
            }catch(_:Exception){status.text="Camera unavailable. Close other camera apps and retry.";retry.isEnabled=true}
        },ContextCompat.getMainExecutor(this))
    }
    private fun analyze(frame: ImageProxy,mirror: Boolean,generation: Int){
        var bitmap: Bitmap?=null
        try {
            val now=SystemClock.uptimeMillis()
            if(dead || !active || complete || posted || generation!=epoch || now-lastFrame<66)return
            lastFrame=now
            if(tracker==null)tracker=LocalPoseTracker(this,silhouette=girth!=null)
            val raw=frame.toBitmap()
            val oriented=LiveCameraFrame.orient(raw,frame.imageInfo.rotationDegrees,mirror)
            if(raw!==oriented)raw.recycle()
            bitmap=oriented
            val result=withBodyScanImage(oriented){input->tracker!!.detect(input,now)}
            val people=result?.landmarks()?.map{row->row.map{BodyProportionScan.Joint(it.x().toDouble(),it.y().toDouble(),it.z().toDouble(),minOf(it.visibility().orElse(0f),it.presence().orElse(0f)).toDouble())}} ?: emptyList()
            val world=result?.worldLandmarks()?.map{row->row.map{BodyProportionScan.Joint(it.x().toDouble(),it.y().toDouble(),it.z().toDouble(),it.visibility().orElse(0f).toDouble())}} ?: emptyList()
            var luminance=0.0;var pixels=0
            for(y in oriented.height/4 until oriented.height*3/4 step 24)for(x in oriented.width/4 until oriented.width*3/4 step 24){
                val c=oriented.getPixel(x,y);luminance+=.2126*Color.red(c)+.7152*Color.green(c)+.0722*Color.blue(c);pixels++
            }
            val light=if(pixels==0)0.0 else luminance/pixels
            val proportions=if(girth==null)scan.add(people,world,oriented.width,oriented.height,now,light) else null
            val masks=result?.segmentationMasks()?.orElse(emptyList()) ?: emptyList()
            val measurements=try {
                val silhouette=masks.singleOrNull()?.let {
                    BodyGirthScan.Mask(it.width,it.height,
                        ByteBufferExtractor.extract(it).order(ByteOrder.nativeOrder()).asFloatBuffer())
                }
                girth?.add(people,world,silhouette,now,light)
            } finally { masks.forEach { it.close() } }
            val guidance=proportions?.guidance ?: measurements?.message.orEmpty()
            val percent=measurements?.percent ?: ((proportions?.progress ?: 0.0)*100).toInt().coerceIn(0,100)
            if(BuildConfig.DEBUG && now-lastDiagnostic>=2000) {
                // State and timing only: never log landmarks, ratios or images.
                lastDiagnostic=now
                Log.i("LuvlyBodyScan","state=$guidance; processingMs=${SystemClock.uptimeMillis()-now}")
            }
            posted=true
            runOnUiThread {
                try {
                    if(dead || !active || generation!=epoch || complete){oriented.recycle();return@runOnUiThread}
                    val old=displayed;displayed=oriented;preview.setImageBitmap(oriented);old?.recycle()
                    guide.updateFrame(oriented.width,oriented.height,percent>0)
                    progress.progress=percent
                    status.text=guidance+if(percent>0) " · $percent%" else ""
                    proportions?.result?.let{finishResult(it)}
                    measurements?.estimate?.let{finishMeasurements(it)}
                }finally{posted=false}
            }
            bitmap=null
        }catch(e:Exception){
            scan.reset()
            girth?.reset()
            if(BuildConfig.DEBUG)Log.w("LuvlyBodyScan","Processing interrupted: ${e.javaClass.simpleName}")
            runOnUiThread{if(!dead && active && generation==epoch){status.text="Tracking could not continue. Tap Retry camera.";progress.progress=0;retry.isEnabled=true}}
        }finally{bitmap?.recycle();frame.close()}
    }
    private fun finishResult(r: BodyProportionScan.Result){
        if(complete || owner!=FirebaseAuth.getInstance().currentUser?.uid){finish();return}
        complete=true;provider?.unbindAll()
        fun rounded(n: Double)=round(n*1000)/1000
        setResult(Activity.RESULT_OK,Intent().putExtra("algorithmVersion",BodyProportionScan.ALGORITHM_VERSION)
            .putExtra("shoulderHipRatio",rounded(r.shoulderHipRatio))
            .putExtra("torsoShoulderRatio",rounded(r.torsoShoulderRatio))
            .putExtra("sampleCount",r.sampleCount).putExtra("durationMs",r.durationMs)
            .putExtra("relativeSpread",rounded(r.relativeSpread)).putExtra("capturedAt",System.currentTimeMillis()))
        finish()
    }
    private fun finishMeasurements(result: BodyGirthScan.Estimate){
        if(complete || owner!=FirebaseAuth.getInstance().currentUser?.uid){finish();return}
        complete=true;provider?.unbindAll()
        setResult(Activity.RESULT_OK,Intent().putExtra("measurementEstimate",true)
            .putExtra("bustCm",round(result.bust)).putExtra("waistCm",round(result.waist))
            .putExtra("hipsCm",round(result.hips)))
        finish()
    }
    override fun onPause(){active=false;epoch++;provider?.unbindAll();if(::preview.isInitialized){preview.setImageDrawable(null);displayed?.recycle();displayed=null};super.onPause()}
    override fun onDestroy(){dead=true;epoch++;provider?.unbindAll();worker.execute{scan.reset();girth?.reset();tracker?.close();tracker=null};worker.shutdown();super.onDestroy()}
}
