package com.luvly.luvly_app.ar

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.app.AlertDialog
import android.os.Handler
import android.os.Looper
import android.os.Bundle
import android.os.CountDownTimer
import android.os.SystemClock
import android.util.Size
import android.view.Choreographer
import android.view.Gravity
import android.view.TextureView
import android.view.View
import android.view.WindowManager
import android.widget.*
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.core.content.ContextCompat
import com.google.mediapipe.framework.image.BitmapImageBuilder
import java.util.concurrent.Executors

/** On-device appearance preview. Images save only on Save look; diagnostic CSV only on explicit export. */
open class TryOnActivity: ComponentActivity(), Choreographer.FrameCallback {
    protected open fun accountLookStore(): LookStore {
        val uid = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
            ?: error("Sign in before saving a look")
        return LookStore(AccountLookDirectory.forUid(noBackupFilesDir, uid))
    }
    private val worker=Executors.newSingleThreadExecutor()
    private val modelReader=Executors.newSingleThreadExecutor()
    private var detector: LocalPoseTracker?=null // worker thread only
    private var armSegmenter: ArmSegmenter?=null // same worker owns the GPU delegate
    private var provider: ProcessCameraProvider?=null
    private var renderer: DressRenderer?=null // main thread only
    private lateinit var image: ImageView
    private lateinit var texture: TextureView
    private lateinit var arms: ArmOcclusionView
    private lateinit var status: TextView
    private lateinit var realignButton: Button
    private lateinit var cameraLabel: TextView
    private lateinit var diagnosticsLabel: TextView
    private var diagnosticsDialog: AlertDialog?=null
    private val diagnostics=TrackingDiagnostics()
    private val trackingTrace=ArTrackingTrace()
    private val targetLock=BodyTargetLock()
    private val sceneLight=SceneLight()
    @Volatile private var targetGeneration=0
    private var pendingTraceExport: String?=null
    private val traceWriter=Executors.newSingleThreadExecutor()
    private val traceExporter=registerForActivityResult(ActivityResultContracts.CreateDocument("text/csv")) { uri ->
        val snapshot=pendingTraceExport;pendingTraceExport=null
        if(uri!=null && snapshot!=null) {
            traceWriter.execute {
                val success=runCatching {
                    val output=contentResolver.openOutputStream(uri,"wt") ?: error("No output stream")
                    output.bufferedWriter(Charsets.UTF_8).use { it.write(snapshot) }
                }.isSuccess
                runOnUiThread { if(!dead)Toast.makeText(this,
                    if(success)"Tracking log saved" else "Could not save log. Please try again.",Toast.LENGTH_LONG).show() }
            }
        } else if(uri!=null)Toast.makeText(this,"Session ended. Please record a new tracking log.",Toast.LENGTH_LONG).show()
    }
    private lateinit var zoom: SeekBar
    private lateinit var switchCamera: Button
    private lateinit var widest: Button
    private lateinit var freezeButton: Button
    private lateinit var controlsButton: Button
    private lateinit var saveButton: Button
    private lateinit var dressTitle: TextView
    private lateinit var changeDressButton: Button
    private var dressPicker: DressPickerDialog?=null
    private var captureHelpDialog: AlertDialog?=null
    @Volatile private var switchingDress=false
    private var dressLoadGeneration=0
    private var saving=false
    private var refiningPreview=false
    private var displayedPoints=emptyList<BodyPoint>()
    private var displayedArmMask: Bitmap?=null
    private var saved=false
    private var frozenAt=0L
    private val readiness=PreviewReadiness()
    private val poseFilter=DressPoseFilter()
    private val turnCalibration=BodyTurnCalibration()
    private val upperBodyPreview=UpperBodyPreview()
    private var photoDelaySeconds=0
    private lateinit var controls: LinearLayout
    private lateinit var controlsPanel: ScrollView
    private lateinit var countdownLabel: TextView
    private var countdown: CountDownTimer?=null
    @Volatile private var frozen=false
    @Volatile private var previewEpoch=0
    private var camera: Camera?=null
    @Volatile private var lensEstimate: SensorLens?=null
    @Volatile private var lensZoom=1f
    @Volatile private var cameraGeneration=0
    private var smoothed: DressPose?=null
    @Volatile private var active=false
    @Volatile private var dead=false
    private var lastFrame=0L
    private var hasLiveFrame=false
    @Volatile private var framePosted=false
    private var front=true
    private var initialized=false
    private var selectedDress: ArDress?=null
    private var generatedDress: ArDress?=null
    private var fullBodyVisible=false

    private val permission=registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) initializeTracking()
        else status.text="Camera permission denied. Close this screen and try again when ready."
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        generatedDress=GeneratedDressFile.resolve(this,intent)
        selectedDress=generatedDress ?: ArDressCatalogue.resolve(intent.getStringExtra("dressId"),intent.getStringExtra("modelAsset"))
        if(selectedDress==null) {
            Toast.makeText(this,"AR preview unavailable for this dress",Toast.LENGTH_LONG).show()
            finish(); return
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val page=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(252,247,244))
            fitsSystemWindows=true
        }
        val header=LinearLayout(this)
        header.addView(action("‹ Dresses") { finish() },buttonLayout())
        changeDressButton=action("Change dress") { chooseDress() }
        header.addView(changeDressButton,buttonLayout())
        page.addView(header)
        dressTitle=TextView(this).apply {
            text=displayName();textSize=20f;gravity=Gravity.CENTER
            setTextColor(Color.rgb(65,42,47));setPadding(12,8,12,12)
        }
        page.addView(dressTitle)
        val stage=FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        image=ImageView(this).apply { scaleType=ImageView.ScaleType.FIT_CENTER }
        texture=TextureView(this).apply { isOpaque=false }
        arms=ArmOcclusionView(this).apply { importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO }
        stage.addView(image,FrameLayout.LayoutParams(-1,-1))
        stage.addView(texture,FrameLayout.LayoutParams(-1,-1))
        stage.addView(arms,FrameLayout.LayoutParams(-1,-1))
        page.addView(stage,LinearLayout.LayoutParams(-1,0,1f))
        status=TextView(this).apply {
            text="Starting camera…"; gravity=Gravity.CENTER;textSize=13f
            val inset=(12*resources.displayMetrics.density).toInt()
            setPadding(inset,inset,inset,inset)
        }
        status.setTextColor(Color.WHITE)
        status.background=GradientDrawable().apply {
            setColor(0xCC302A2B.toInt());cornerRadius=12*resources.displayMetrics.density
        }
        val trackingHud=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL }
        trackingHud.addView(status)
        realignButton=action("Re-align dress here") {
            if(!frozen && !dead && !switchingDress) {
                cancelCountdown();resetTracking();updateDress();showControls(false)
                status.text="Finding you · Face forward with both shoulders visible"
            }
        }.apply { visibility=View.GONE }
        trackingHud.addView(realignButton)
        diagnosticsLabel=TextView(this).apply {
            textSize=11f;setTextColor(Color.WHITE);setPadding(12,6,12,6)
            setBackgroundColor(0xBB302A2B.toInt());visibility=View.GONE
            setOnClickListener { showDiagnosticsDetails() }
        }
        trackingHud.addView(diagnosticsLabel)
        stage.addView(trackingHud,FrameLayout.LayoutParams(-1,-2,Gravity.TOP).apply {
            val margin=(12*resources.displayMetrics.density).toInt()
            setMargins(margin,margin,margin,0)
        })
        countdownLabel=TextView(this).apply {
            textSize=18f; gravity=Gravity.CENTER; setTextColor(Color.WHITE)
            val pad=(12*resources.displayMetrics.density).toInt()
            setPadding(pad,pad,pad,pad)
            background=GradientDrawable().apply {
                setColor(0xCC302A2B.toInt());cornerRadius=12*resources.displayMetrics.density
            }
            visibility=View.GONE
        }
        stage.addView(countdownLabel,FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
            bottomMargin=(16*resources.displayMetrics.density).toInt()
        })
        // Overlay the controls instead of resizing the camera/pose coordinate system.
        controls=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(252,247,244))
        }
        controlsPanel=ScrollView(this).apply {
            visibility=View.GONE
            addView(controls)
        }
        stage.addView(controlsPanel,FrameLayout.LayoutParams(-1,0,Gravity.BOTTOM))
        stage.addOnLayoutChangeListener { _,_,top,_,bottom,_,_,_,_ ->
            controlsPanel.layoutParams=controlsPanel.layoutParams.apply {
                height=((bottom-top)*.45f).toInt()
            }
        }
        val cameraControls=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL }
        switchCamera=Button(this).apply {
            text="Switch camera"; isEnabled=false
            setOnClickListener { bindCamera(!front) }
        }
        widest=Button(this).apply {
            text="Widest view"; isEnabled=false
            setOnClickListener { requestZoom(0f) }
        }
        cameraControls.addView(switchCamera,LinearLayout.LayoutParams(0,-2,1f))
        cameraControls.addView(widest,LinearLayout.LayoutParams(0,-2,1f))
        controls.addView(cameraControls)
        cameraLabel=TextView(this).apply { text="Checking camera zoom range…"; gravity=Gravity.CENTER; textSize=12f }
        controls.addView(cameraLabel)
        zoom=SeekBar(this).apply {
            max=100; isEnabled=false; contentDescription="Camera zoom: left is widest"
            setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?,p: Int,user: Boolean) {
                    if(user) requestZoom(p/100f)
                }
                override fun onStartTrackingTouch(s: SeekBar?) {}
                override fun onStopTrackingTouch(s: SeekBar?) {}
            })
        }
        controls.addView(zoom)
        controls.addView(action("Re-align dress") { if(!frozen) { resetTracking();updateDress();showControls(false) } })
        controls.addView(TextView(this).apply {
            text="Start facing forward near the centre. We keep following that position, not a face identity. If you move to a new spot or change people, use Re-align dress. Keep mirrors and other people outside the view when possible."
            textSize=12f;setPadding(12,8,12,12)
        })
        val timerButton=action("Photo timer · Off") { }
        timerButton.setOnClickListener {
            AlertDialog.Builder(this).setTitle("Photo timer")
                .setSingleChoiceItems(arrayOf("Off · Capture when ready","3 seconds","10 seconds · Hands-free"),
                    listOf(0,3,10).indexOf(photoDelaySeconds)) { dialog,index ->
                    photoDelaySeconds=listOf(0,3,10)[index]
                    timerButton.text=if(photoDelaySeconds==0)"Photo timer · Off" else "Photo timer · ${photoDelaySeconds}s"
                    dialog.dismiss()
                }.setNegativeButton("Cancel",null).show()
        }
        controls.addView(timerButton)
        controls.addView(TextView(this).apply {
            text="Face forward briefly to align, then turn slowly left or right.\nKeep the phone upright near waist/chest height; include your feet for full length.\nLive try-on continues until you take a photo.\nProcessed on-device • No size/fit guarantee"
            textSize=12f; gravity=Gravity.CENTER; setPadding(12,8,12,16)
        })
        val diagnosticsButton=action("Show live diagnostics") { }
        diagnosticsButton.setOnClickListener {
            val show=diagnosticsLabel.visibility!=View.VISIBLE
            diagnosticsLabel.visibility=if(show)View.VISIBLE else View.GONE
            diagnosticsLabel.text=diagnostics.compact(SystemClock.uptimeMillis())
            diagnosticsButton.text=if(show)"Hide live diagnostics" else "Show live diagnostics"
            showControls(false)
        }
        controls.addView(diagnosticsButton)
        controls.addView(action("Export tracking log") { exportTrackingTrace() })
        controls.addView(action("Clear tracking log") {
            trackingTrace.clear()
            Toast.makeText(this,"Tracking log cleared",Toast.LENGTH_SHORT).show()
        })
        val actions=LinearLayout(this).apply { orientation=LinearLayout.HORIZONTAL }
        controlsButton=Button(this).apply {
            text="Camera"
            setOnClickListener { showControls(controlsPanel.visibility!=View.VISIBLE) }
        }
        freezeButton=Button(this).apply {
            text="Take photo"; isEnabled=false
            setOnClickListener {
                when {
                    frozen -> resumePreview()
                    countdown!=null -> cancelCountdown()
                    photoDelaySeconds>0 -> startCountdown()
                    readiness.ready(SystemClock.uptimeMillis()) -> freezeReadyPreview()
                    smoothed!=null -> waitForFreshPreview()
                    else -> showCaptureHelp()
                }
            }
        }
        actions.addView(controlsButton,buttonLayout())
        actions.addView(freezeButton,buttonLayout())
        saveButton=action("Save look") { saveLook() }.apply { isEnabled=false;visibility=View.GONE }
        actions.addView(saveButton,buttonLayout())
        styleButton(controlsButton);styleButton(freezeButton)
        page.addView(actions)
        page.addView(TextView(this).apply {
            text="Appearance preview · About & privacy";textSize=12f;gravity=Gravity.CENTER
            setPadding(10,12,10,16);setTextColor(Color.rgb(139,65,83))
            setOnClickListener { AlertDialog.Builder(this@TryOnActivity)
                .setTitle("Before you decide")
                .setMessage("Compare the style, not the size. Face forward briefly to align, then turn slowly left or right. Side previews require reliable shoulder and hip tracking and may pause when landmarks are hidden. Back views and deep forward/backward leaning are not supported. Placement, shape and depth are approximate. This does not measure fit, scan your body, simulate cloth or remove your existing clothes. Foreground arm coverage is approximate; keep arms slightly apart for the clearest view. Colours vary with lighting and screen. Confirm size and colour at a real fitting.\n\nLive try-on continues until Take photo. A photo is frozen, not saved, until Save look. An optional timer is in Camera.\n\nCamera frames stay on this phone. Saved looks belong to your signed-in account on this phone, are excluded from backup, and are removed when the app is uninstalled.\n\n${selectedDress?.label}\nReference studies are not verified shop inventory.")
                .setPositiveButton("Got it",null).show() }
        })
        setContentView(page)
        try {
            renderer=DressRenderer(this,texture,selectedDress!!.asset,selectedDress!!.anchors)
            beginCameraExperience()
        } catch (e: Exception) { status.text="3D preview unavailable on this device. Please close and retry." }
    }

    private fun showCaptureHelp() {
        if(dead || captureHelpDialog?.isShowing==true)return
        captureHelpDialog=AlertDialog.Builder(this)
            .setTitle("Not ready to take a photo")
            .setMessage("Face the camera and keep your shoulders and hips in view. Hold still briefly while the dress aligns.\n\nFor hands-free photos, open Camera and choose a 3- or 10-second photo timer.\n\nNo photo has been taken.")
            .setPositiveButton("Open Camera settings") { _,_ -> showControls(true) }
            .setNegativeButton("Back to try-on",null)
            .create().also { dialog ->
                dialog.setOnDismissListener { captureHelpDialog=null }
                // A standard scrollable message, not a two-line transient Toast.
                dialog.show()
            }
    }

    protected fun exportTrackingTrace() {
        if(dead || pendingTraceExport!=null)return
        if(trackingTrace.size==0) {
            Toast.makeText(this,"No tracking events yet",Toast.LENGTH_SHORT).show();return
        }
        AlertDialog.Builder(this).setTitle("Export tracking log")
            .setMessage("Save recent tracking diagnostics (up to 3 minutes / 900 events). This contains angles, confidence, processing times and reasons the dress was hidden — not photos, audio, account details or body measurements.\n\nChoose Downloads to keep the file on this phone. Nothing is sent automatically. You can share the CSV yourself for troubleshooting. Leaving try-on clears the in-memory log.")
            .setNegativeButton("Cancel",null)
            .setPositiveButton("Save CSV") { _,_ ->
                pendingTraceExport=trackingTrace.csv(com.luvly.luvly_app.BuildConfig.VERSION_CODE)
                try { traceExporter.launch("luvly-ar-trace-${com.luvly.luvly_app.BuildConfig.VERSION_CODE}.csv") }
                catch(e: Exception) { pendingTraceExport=null;Toast.makeText(this,"File picker unavailable",Toast.LENGTH_SHORT).show() }
            }.show()
    }

    private fun showDiagnosticsDetails() {
        if(dead || diagnosticsDialog?.isShowing==true)return
        diagnosticsDialog=AlertDialog.Builder(this).setTitle("Tracking details · Snapshot")
            .setMessage(if(frozen)"Frozen photo · Resume live to see tracking diagnostics" else diagnostics.description(SystemClock.uptimeMillis()))
            .setNeutralButton("Export log") { _,_ -> exportTrackingTrace() }
            .setPositiveButton("Back to live view",null).create().also { dialog ->
                dialog.setOnDismissListener { diagnosticsDialog=null };dialog.show()
            }
    }

    /** Debug fixtures can display the same compact HUD without opening a real camera. */
    protected fun showTrackingDiagnostics() { diagnosticsLabel.visibility=View.VISIBLE }

    protected open fun beginCameraExperience() {
        if (ContextCompat.checkSelfPermission(this,Manifest.permission.CAMERA)==PackageManager.PERMISSION_GRANTED)
            initializeTracking()
        else permission.launch(Manifest.permission.CAMERA)
    }

    private fun updateDress() {
        renderer?.update(smoothed,1f)
    }

    private fun resetTracking() {
        synchronized(targetLock) { targetGeneration++;targetLock.reset() }
        sceneLight.reset()
        trackingTrace.record(SystemClock.uptimeMillis(),"tracking_reset")
        diagnostics.reset()
        readiness.reset();poseFilter.reset();turnCalibration.reset();upperBodyPreview.reset();smoothed=null
        displayedPoints=emptyList();displayedArmMask=null
        if(::arms.isInitialized)arms.update(null)
        if(::texture.isInitialized)texture.alpha=0f
        if(::realignButton.isInitialized)realignButton.visibility=View.GONE
    }

    /** Debug fixtures inspect display state only; no camera pixels or user data. */
    protected fun trackingDisplayProbe(): Triple<Boolean,Float,Boolean> =
        Triple(smoothed!=null,texture.alpha,readiness.ready(SystemClock.uptimeMillis()))
    protected fun spatialPoseProbe(): SpatialDressPose?=smoothed?.spatial
    protected fun shoulderTiltProbe(): Float?=smoothed?.shoulderTilt
    protected fun trackingTraceProbe(): String = trackingTrace.csv(com.luvly.luvly_app.BuildConfig.VERSION_CODE)
    protected fun setFixturePhotoDelay(seconds: Int) {
        check(com.luvly.luvly_app.BuildConfig.DEBUG && seconds in listOf(0,3,10))
        photoDelaySeconds=seconds
    }

    private fun updatePreviewButton() {
        if(!::freezeButton.isInitialized)return
        val enabled=PreviewEligibility.canPress(active && !dead && !switchingDress,renderer!=null,
            hasLiveFrame,frozen,countdown!=null,saving)
        if(freezeButton.isEnabled!=enabled)freezeButton.isEnabled=enabled
    }

    private fun displayName(): String = selectedDress?.label?.substringBefore(" •") ?: "Dress preview"
    private fun buttonLayout() = LinearLayout.LayoutParams(0,-2,1f).apply {
        val margin=(4*resources.displayMetrics.density).toInt()
        setMargins(margin,margin,margin,margin)
    }
    private fun styleButton(button: Button) {
        val dp=resources.displayMetrics.density
        button.isAllCaps=false;button.textSize=13f;button.minHeight=(48*dp).toInt()
        button.setTextColor(Color.WHITE)
        fun background(color: Int)=GradientDrawable().apply { setColor(color);cornerRadius=12*dp }
        button.background=StateListDrawable().apply {
            addState(intArrayOf(-android.R.attr.state_enabled),background(Color.rgb(171,158,160)))
            addState(intArrayOf(android.R.attr.state_pressed),background(Color.rgb(124,55,72)))
            addState(intArrayOf(),background(Color.rgb(161,79,98)))
        }
    }
    private fun action(label: String,run: ()->Unit): Button = Button(this).apply {
        text=label;styleButton(this);setOnClickListener { run() }
    }
    private fun chooseDress() {
        if(saving || switchingDress || dressPicker!=null)return
        if(!frozen)cancelCountdown()
        val choices=ArDressCatalogue.all()+listOfNotNull(generatedDress)
        dressPicker=DressPickerDialog(this,choices,selectedDress?.id,frozen && !saved) { next ->
            switchDress(next)
        }.also { dialog ->
            dialog.setOnDismissListener { dressPicker=null }
            dialog.show()
        }
    }

    /** Read local GLB bytes off-thread. One main-thread renderer owns all GPU resources. */
    protected fun switchDress(next: ArDress) {
        val targetRenderer=renderer ?: return
        if(dead || !active || saving || switchingDress || next.id==selectedDress?.id ||
            (next!=generatedDress && ArDressCatalogue.resolve(next.id,next.asset)!=next))return
        cancelCountdown();showControls(false)
        previewEpoch++ // Reject camera work queued for the old model / anchors.
        refiningPreview=false
        val generation=++dressLoadGeneration
        setDressLoading(true)
        status.text="Loading ${next.name}…"
        modelReader.execute {
            val bytes=runCatching { readDressModel(next) }
            runOnUiThread {
                if(dead || !active || generation!=dressLoadGeneration || renderer!==targetRenderer)return@runOnUiThread
                fun finish(success: Boolean) {
                    if(dead || generation!=dressLoadGeneration)return
                    setDressLoading(false)
                    if(success) {
                        selectedDress=next;dressTitle.text=displayName()
                        resumePreview() // Discard old alignment only after the model commits.
                    } else {
                        updateDress() // Keep the previous dress and frozen preview on failure.
                        status.text="Could not load ${next.name}. Your previous dress is still selected."
                        Toast.makeText(this,status.text,Toast.LENGTH_LONG).show()
                        if(frozen)refineFrozenArms()
                    }
                }
                val buffer=bytes.getOrNull()
                if(buffer==null)finish(false)
                else try { targetRenderer.loadDress(buffer,next.anchors) { finish(it) } }
                catch(_:Exception) { finish(false) }
            }
        }
    }

    private fun setDressLoading(loading: Boolean) {
        switchingDress=loading
        changeDressButton.isEnabled=!loading && !saving
        changeDressButton.text=if(loading) "Loading…" else "Change dress"
        controlsButton.isEnabled=!loading && !saving
        saveButton.isEnabled=!loading && frozen && !saving && !saved && !refiningPreview
        switchCamera.isEnabled=!loading && !frozen && provider?.let {
            it.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) && it.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
        }==true
        widest.isEnabled=!loading && !frozen && camera!=null
        zoom.isEnabled=!loading && !frozen && camera?.cameraInfo?.zoomState?.value?.let {
            it.maxZoomRatio>it.minZoomRatio
        }==true
        updatePreviewButton()
    }

    /** Debug fixtures use the real picker and model switch without camera access. */
    protected fun dressSwitchProbe()=Triple(selectedDress?.id,switchingDress,renderer)
    protected fun dressPickerWindow()=dressPicker?.window
    protected open fun readDressModel(dress: ArDress)=DressRenderer.readModel(this,dress.asset)

    private fun saveLook() {
        if(!frozen || saving || switchingDress || refiningPreview || saved || smoothed==null || renderer==null ||
            SystemClock.uptimeMillis()-frozenAt<250)return
        val source=(image.drawable as? BitmapDrawable)?.bitmap ?: return
        val layer=texture.bitmap ?: return
        val bounds=PoseAlignment.imageBounds(source.width,source.height,image.width,image.height)
        val rect=Rect(bounds[0],bounds[1],bounds[2],bounds[3])
        if(rect.width()<=0 || rect.height()<=0) { layer.recycle();return }
        // Reject a missing GPU overlay instead of silently saving only the camera.
        var visible=false
        for(y in rect.top until minOf(rect.bottom,layer.height) step 24)
            for(x in rect.left until minOf(rect.right,layer.width) step 24)
                if(Color.alpha(layer.getPixel(x,y))>16)visible=true
        if(!visible) { layer.recycle();Toast.makeText(this,"Photo is not ready. Resume live and try again.",Toast.LENGTH_LONG).show();return }
        val capturedDress=selectedDress!!;val capturedFullBody=fullBodyVisible
        val caption=android.text.TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color=Color.rgb(65,42,47);textSize=rect.width()/40f
        }
        val text="Luvly · ${capturedDress.label}\nAppearance only · Not a size/fit assessment"+
            (if(capturedFullBody) "" else " · Cropped hem")+
            (when(capturedDress.id) {
                "princess-wedding" -> "\nAdapted from Messrs · sketchfab.com/vodiencongtu\nCC BY 4.0 · creativecommons.org/licenses/by/4.0/"
                "elegant-local-review" -> "\nAdapted model · Private local review · Not verified shop stock"
                else -> "\nApproximate reference study · Not verified shop stock"
            })
        val footer=android.text.StaticLayout.Builder.obtain(text,0,text.length,caption,rect.width()-32)
            .setIncludePad(false).build()
        val snapshot=Bitmap.createBitmap(rect.width(),rect.height()+footer.height+32,Bitmap.Config.ARGB_8888)
        val canvas=Canvas(snapshot);canvas.drawColor(Color.rgb(252,247,244))
        canvas.save();canvas.clipRect(0,0,rect.width(),rect.height())
        canvas.translate(-rect.left.toFloat(),-rect.top.toFloat())
        image.draw(canvas);canvas.drawBitmap(layer,0f,0f,null)
        arms.draw(canvas) // Same occlusion as the frozen on-screen composite.
        canvas.restore();layer.recycle()
        canvas.save();canvas.translate(16f,rect.height()+16f);footer.draw(canvas);canvas.restore()
        saving=true;saveButton.isEnabled=false;freezeButton.isEnabled=false;controlsButton.isEnabled=false;changeDressButton.isEnabled=false
        status.text="Saving this look on your phone…"
        Thread {
            val error=runCatching {
                val store=accountLookStore()
                store.save(capturedDress.id,capturedFullBody,capturedDress.name) {
                    check(snapshot.compress(Bitmap.CompressFormat.PNG,100,it))
                }
            }.exceptionOrNull()
            snapshot.recycle()
            runOnUiThread {
                saving=false
                if(!dead) {
                    saved=error==null;saveButton.isEnabled=!saved && frozen
                    freezeButton.isEnabled=true;controlsButton.isEnabled=true;changeDressButton.isEnabled=true
                    status.text=if(saved) "Saved to My try-on looks · Only on this phone"
                        else "Could not save. Check storage or delete an older look, then retry."
                    saveButton.text=if(saved) "Saved ✓" else "Save look"
                }
            }
        }.start()
    }

    private fun showControls(show: Boolean) {
        if(show && countdown!=null)cancelCountdown()
        if(show)diagnosticsLabel.text=if(frozen) "Frozen photo · Resume live for diagnostics"
            else diagnostics.compact(SystemClock.uptimeMillis())
        controlsPanel.visibility=if(show) View.VISIBLE else View.GONE
        controlsButton.text=if(show) "Close camera" else "Camera"
    }

    private fun cancelCountdown() {
        countdown?.cancel(); countdown=null
        countdownLabel.visibility=View.GONE
        freezeButton.text=if(frozen) "Resume live" else "Take photo"
        updatePreviewButton()
    }

    private fun startCountdown() {
        if(!PreviewEligibility.canPress(active && !dead && !switchingDress,renderer!=null,
            hasLiveFrame,false,false,saving))return
        showControls(false)
        freezeButton.text="Cancel timer"
        countdownLabel.visibility=View.VISIBLE
        countdown=object: CountDownTimer(photoDelaySeconds*1000L,100) {
            override fun onTick(remaining: Long) {
                countdownLabel.text="Photo in ${(remaining+999)/1000}s · Tap Cancel timer to stop"
            }
            override fun onFinish() {
                countdown=null; countdownLabel.visibility=View.GONE
                if(!active || dead) return
                if(smoothed==null || !readiness.ready(SystemClock.uptimeMillis())) {
                    waitForFreshPreview()
                    return
                }
                freezeReadyPreview()
            }
        }.start()
        updatePreviewButton()
    }

    /** Allow a short recovery window, never freeze a stale or invalid pose. */
    private fun waitForFreshPreview() {
        freezeButton.text="Cancel timer"
        countdownLabel.visibility=View.VISIBLE
        countdownLabel.text="Waiting for a clear pose…"
        val recovery=PreviewRecovery(SystemClock.uptimeMillis())
        countdown=object: CountDownTimer(3000,100) {
            override fun onTick(remaining: Long) {
                if(!active || dead) { cancelCountdown(); return }
                if(recovery.canCapture(SystemClock.uptimeMillis(),smoothed!=null &&
                    renderer!=null && readiness.ready(SystemClock.uptimeMillis()))) {
                    cancelCountdown();freezeReadyPreview()
                }
            }
            override fun onFinish() {
                cancelCountdown()
                if(active && !dead) Toast.makeText(this@TryOnActivity,
                    "No photo taken. Live try-on continues; face forward to align and try again.",Toast.LENGTH_LONG).show()
            }
        }.start()
        updatePreviewButton()
    }

    private fun freezeReadyPreview() {
                if(!active || dead || smoothed==null || renderer==null ||
                    !readiness.ready(SystemClock.uptimeMillis()))return
                countdownLabel.visibility=View.GONE
                countdown?.cancel();countdown=null
                frozen=true; previewEpoch++
                realignButton.visibility=View.GONE
                texture.alpha=1f // The saved GPU layer must match the frozen screen.
                frozenAt=SystemClock.uptimeMillis();saved=false
                freezeButton.text="Resume live";saveButton.isEnabled=false;saveButton.visibility=View.VISIBLE
                updatePreviewButton()
                Handler(Looper.getMainLooper()).postDelayed({
                    if(!dead && frozen && !switchingDress && !saving && !refiningPreview && !saved)saveButton.isEnabled=true
                },250)
                switchCamera.isEnabled=false; widest.isEnabled=false; zoom.isEnabled=false
                status.text=(if(fullBodyVisible) "PHOTO · Frozen preview" else "PHOTO · Hem outside view")+"\nNot saved · Resume live or save this look"
                refineFrozenArms()
    }

    /** Slow phones get the same edge refinement on the frozen image, without slowing live tracking. */
    private fun refineFrozenArms() {
        if(saved || saving || refiningPreview || displayedArmMask!=null || displayedPoints.isEmpty())return
        val source=(image.drawable as? BitmapDrawable)?.bitmap ?: return
        val points=displayedPoints.toList()
        if(ArmOcclusion.capsules(points,source.width,source.height,skinIntersection=true).isEmpty())return
        val epoch=previewEpoch
        refiningPreview=true;saveButton.isEnabled=false
        status.text="Refining your preview…"
        worker.execute {
            val mask=runCatching { armSegmenter?.mask(source,points,live=false) }.getOrNull()
            runOnUiThread {
                if(dead || !frozen || epoch!=previewEpoch) { mask?.recycle();return@runOnUiThread }
                displayedArmMask=mask;arms.update(source,mask)
                refiningPreview=false
                status.text=(if(fullBodyVisible) "PHOTO · Frozen preview" else "PHOTO · Hem outside view")+
                    "\nNot saved · Resume live or save this look"
                Handler(Looper.getMainLooper()).postDelayed({
                    if(!dead && frozen && epoch==previewEpoch && !saving && !saved)saveButton.isEnabled=true
                },250)
            }
        }
    }

    private fun resumePreview() {
        cancelCountdown(); previewEpoch++; frozen=false;refiningPreview=false
        freezeButton.text="Take photo";saveButton.visibility=View.GONE
        resetTracking();hasLiveFrame=false;saved=false;saveButton.isEnabled=false
        saveButton.text="Save look"
        smoothed=null; renderer?.update(null,1f)
        image.setImageDrawable(null)
        updatePreviewButton()
        val p=provider
        switchCamera.isEnabled=p!=null && p.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA) && p.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
        widest.isEnabled=camera!=null
        zoom.isEnabled=camera?.cameraInfo?.zoomState?.value?.let { it.maxZoomRatio>it.minZoomRatio } ?: false
        status.text="LIVE · Face forward briefly to align"
    }

    private fun initializeTracking() {
        if (initialized || dead) return
        initialized=true
        worker.execute {
            try {
                detector=LocalPoseTracker(this)
                armSegmenter=ArmSegmenter(this)
                runOnUiThread { if (!dead) bindCamera() }
            } catch (e: Exception) {
                runOnUiThread { if (!dead) status.text="Body tracker could not start. Check the installed model and restart." }
            }
        }
    }

    private fun bindCamera(requestedFront: Boolean?=null) {
        cancelCountdown(); frozen=false; resetTracking();hasLiveFrame=false;previewEpoch++; freezeButton.isEnabled=false
        saved=false;saveButton.isEnabled=false
        switchCamera.isEnabled=false; widest.isEnabled=false; zoom.isEnabled=false
        val generation=++cameraGeneration
        camera?.cameraInfo?.zoomState?.removeObservers(this)
        camera=null
        lensEstimate=null;lensZoom=1f
        smoothed=null; renderer?.update(null,1f); image.setImageDrawable(null)
        status.text="Starting camera…"
        val future=ProcessCameraProvider.getInstance(this)
        future.addListener({
            if (dead || generation!=cameraGeneration) return@addListener
            try {
                val cameraProvider=future.get()
                provider=cameraProvider
                val hasFront=cameraProvider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)
                val hasBack=cameraProvider.hasCamera(CameraSelector.DEFAULT_BACK_CAMERA)
                front=requestedFront ?: hasFront
                val selector=if(front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA
                val mirror=front
                // Balanced live preview: avoid rotating/uploading a 960x720 frame
                // only to downsample it again for inference. The frozen look uses
                // this same matched frame; this is not a high-resolution photograph.
                val analysis=ImageAnalysis.Builder().setResolutionSelector(ResolutionSelector.Builder()
                    .setResolutionStrategy(ResolutionStrategy(Size(640,480),
                        ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER)).build())
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888).build()
                analysis.setAnalyzer(worker) { frame -> analyze(frame,mirror,generation) }
                cameraProvider.unbindAll()
                val bound=cameraProvider.bindToLifecycle(this,selector,analysis)
                camera=bound
                lensEstimate=CameraLensEstimate.read(bound.cameraInfo)
                freezeButton.isEnabled=false
                switchCamera.isEnabled=hasFront && hasBack
                switchCamera.text=if(front) "Rear camera" else "Front camera"
                widest.isEnabled=true
                bound.cameraInfo.zoomState.observe(this) { state ->
                    if(camera!==bound) return@observe
                    lensZoom=state.zoomRatio
                    zoom.isEnabled=!frozen && state.maxZoomRatio>state.minZoomRatio
                    zoom.progress=(state.linearZoom*100).toInt()
                    val lens=if(front) "Front" else "Rear"
                    cameraLabel.text=String.format(java.util.Locale.US,
                        "%s • %.1f× • widest %.1f×\n%s",lens,state.zoomRatio,state.minZoomRatio,
                        if(state.minZoomRatio>=1f) "This lens cannot zoom out below 1×. Try the other camera."
                        else "Slide left for a wider view; right to zoom in.")
                }
                requestZoom(0f)
            } catch (e: Exception) {
                status.text="Camera unavailable. Close other camera apps and retry."
                cameraLabel.text="Could not open camera. Try switching cameras."
                switchCamera.isEnabled=true
            }
        },ContextCompat.getMainExecutor(this))
    }

    private fun requestZoom(value: Float) {
        if(frozen) return
        val bound=camera ?: return
        val result=bound.cameraControl.setLinearZoom(value.coerceIn(0f,1f))
        result.addListener({
            if(dead || camera!==bound) return@addListener
            try { result.get() } catch (e: Exception) {
                if(e.cause !is CameraControl.OperationCanceledException)
                    cameraLabel.text="Zoom could not be changed. Please try again."
            }
        },ContextCompat.getMainExecutor(this))
    }

    private fun analyze(frame: ImageProxy, mirror: Boolean, generation: Int) {
        var bitmap: Bitmap?=null
        var pendingMask: Bitmap?=null
        val epoch=previewEpoch
        val targetEpoch=targetGeneration
        try {
            val now=SystemClock.uptimeMillis()
            if (!active || dead || frozen || switchingDress || framePosted || generation!=cameraGeneration || now-lastFrame<66 || detector==null) return
            lastFrame=now
            // CameraX's RGBA conversion respects device row/pixel strides.
            val raw=frame.toBitmap()
            // CameraX may negotiate a larger stream (2094 device trace: 1024x768).
            // Rotate, mirror and resize in one allocation, keeping the full frame.
            val rotated=LiveCameraFrame.orient(raw,frame.imageInfo.rotationDegrees,mirror)
            if (raw!==rotated) raw.recycle()
            bitmap=rotated
            // Normalized landmarks map back to the exact same oriented camera frame.
            // Keep inference separate, so a sharper preview does not mean a larger detector input.
            val ratio=640f/maxOf(rotated.width,rotated.height)
            val inference=if(ratio<1f) Bitmap.createScaledBitmap(rotated,
                (rotated.width*ratio).toInt(),(rotated.height*ratio).toInt(),true)
                else rotated.copy(Bitmap.Config.ARGB_8888,false)
            val input=BitmapImageBuilder(inference).build()
            val poseStarted=SystemClock.uptimeMillis()
            val result=try { detector!!.detect(input,now) } finally { input.close();inference.recycle() }
            if(result==null) {
                rotated.recycle();bitmap=null
                runOnUiThread {
                    if(!dead && active && !frozen && epoch==previewEpoch && generation==cameraGeneration) {
                        resetTracking();renderer?.update(null,1f);updatePreviewButton()
                        status.text="Tracker restarted · Face forward briefly to resume"
                    }
                }
                return
            }
            val poseFinished=SystemClock.uptimeMillis()
            val people=result.landmarks().map { landmarks->landmarks.map {
                BodyPoint(it.x(),it.y(),minOf(it.visibility().orElse(0f),it.presence().orElse(0f)),it.z())
            } }
            val target=synchronized(targetLock) {
                if(targetEpoch!=targetGeneration || poseFinished-now !in 0..700)
                    BodyTargetLock.Selection(null,"target_stale")
                else targetLock.select(people,rotated.width,rotated.height,now)
            }
            val points=target.index?.let { people[it] } ?: emptyList()
            // Image/world pairs MUST use the same detector index. List order can
            // change between frames; it is never treated as a persistent identity.
            val world=target.index?.let { result.worldLandmarks().getOrNull(it) }?.map {
                WorldBodyPoint(it.x(),it.y(),it.z(),it.visibility().orElse(0f))
            } ?: emptyList()
            val projection=lensEstimate?.frame(frame.width,frame.height,frame.imageInfo.rotationDegrees,lensZoom)
                ?.resized(rotated.width,rotated.height)
                ?: FrameProjection.estimated(rotated.width,rotated.height)
            val maskStarted=SystemClock.uptimeMillis()
            val armMask=armSegmenter?.mask(rotated,points,processingBeforeMaskMs=maskStarted-now)
            val segmenter=armSegmenter
            val timings=FrameTimings(poseStarted-now,poseFinished-poseStarted,SystemClock.uptimeMillis()-maskStarted,
                segmenter?.lastMode ?: "unavailable",
                detector!!.backend,detector!!.modelName)
            pendingMask=armMask
            framePosted=true
            runOnUiThread {
                try {
                    if (dead || !active || frozen || switchingDress || epoch!=previewEpoch || generation!=cameraGeneration || targetEpoch!=targetGeneration) {
                        rotated.recycle();armMask?.recycle();return@runOnUiThread
                    }
                    displayCameraFrame(rotated,points,now,armMask,world,projection,timings,
                        target.reason,target.resetAlignment,people.size,target.index,target.retainCalibration)
                } finally { framePosted=false }
            }
            bitmap=null // Ownership transferred to the ImageView / UI callback.
            pendingMask=null
        } catch (e: Exception) {
            bitmap?.recycle()
            pendingMask?.recycle()
            runOnUiThread { if(!dead && !frozen && epoch==previewEpoch && generation==cameraGeneration) {
                resetTracking();renderer?.update(null,1f);updatePreviewButton()
                status.text="Tracking interrupted. Close and reopen live try-on."
            } }
        } finally { frame.close() }
    }

    /** Common display path; debug-only fixture supplies synthetic frames without opening a camera. */
    protected fun displayCameraFrame(rotated: Bitmap, points: List<BodyPoint>, capturedAt: Long=SystemClock.uptimeMillis(), armMask: Bitmap?=null,
                                    world: List<WorldBodyPoint>?=null, projection: FrameProjection?=null,timings: FrameTimings?=null,
                                    targetReason: String?=null,resetAlignment: Boolean=false,detectedPeople: Int?=null,targetIndex: Int?=null,
                                    retainCalibration: Boolean=false) {
                if(dead || !active || frozen || switchingDress)return
                if(resetAlignment) {
                    // Always discard stale display/capture evidence. Only tightly
                    // confirmed brief returns may reuse unexpired front calibration.
                    readiness.reset();poseFilter.reset();smoothed=null
                    if(!retainCalibration) { turnCalibration.reset();upperBodyPreview.reset() }
                    trackingTrace.record(SystemClock.uptimeMillis(),
                        if(retainCalibration)"target_display_reset" else "target_alignment_reset")
                }
                val targetBlocked=targetReason!=null && targetReason !in listOf("target_acquired","target_tracked","target_reacquired")
                // Display the very same oriented bitmap used for inference: no preview crop mismatch.
                image.setImageBitmap(rotated)
                val bounds=PoseAlignment.imageBounds(rotated.width,rotated.height,image.width,image.height)
                texture.clipBounds=Rect(bounds[0],bounds[1],bounds[2],bounds[3])
                hasLiveFrame=true
                val now=SystemClock.uptimeMillis()
                val imagePose=if(now-capturedAt in 0..700)
                    PoseAlignment.align(points,rotated.width,rotated.height,image.width,image.height,selectedDress!!.anchors)
                    else null
                // Only legacy debug fixtures omit world data. Live inference always
                // supplies it (even empty), and never quietly falls back to a 2D sticker.
                val pose=if(targetBlocked) { turnCalibration.pauseForTarget(now);null }
                    else if(now-capturedAt !in 0..700)null else if(world==null)imagePose else {
                        val frame=projection ?: FrameProjection.estimated(rotated.width,rotated.height)
                        if(UpperBodyPreview.eligible(points,rotated.width,rotated.height))
                            upperBodyPreview.register(points,world,rotated.width,rotated.height,image.width,image.height,
                                selectedDress!!.anchors,frame,now)
                        else turnCalibration.register(points,world,rotated.width,rotated.height,image.width,image.height,
                            selectedDress!!.anchors,frame,now)
                    }
                // Input timestamp still controls capture readiness below. Presentation
                // grace starts only when this processed result actually reaches the UI.
                val traceDelta=poseFilter.diagnosticDelta(pose,now,selectedDress!!.anchors.shoulderWidth)
                var filtered=poseFilter.observe(pose,now,selectedDress!!.anchors.shoulderWidth)
                val safetyReason=if(targetBlocked)"target_unconfirmed" else if(!filtered.accepted)PoseDisplaySafety.hideReason(filtered.pose,points,
                        rotated.width,rotated.height,image.width,image.height,selectedDress!!.anchors) else null
                if(safetyReason!=null) {
                    poseFilter.suppressHeldDisplay()
                    filtered=poseFilter.displayAt(now)
                }
                smoothed=filtered.pose
                if(filtered.accepted) {
                    pose?.let { upperBodyPreview.remember(it,now) }
                    // Sample around the wearer, avoiding a bright ceiling dominating
                    // the bounded brightness correction. Not environment light recovery.
                    val body=(if(UpperBodyPreview.isUpper(pose))listOf(11,12) else listOf(11,12,23,24)).mapNotNull { points.getOrNull(it) }
                    val x0=((body.minOfOrNull { it.x } ?: .25f)-.15f).coerceIn(.05f,.75f)
                    val x1=((body.maxOfOrNull { it.x } ?: .75f)+.15f).coerceIn(x0+.1f,.95f)
                    val y0=((body.minOfOrNull { it.y } ?: .25f)-.06f).coerceIn(.05f,.75f)
                    val y1=((body.maxOfOrNull { it.y } ?: .75f)+.12f).coerceIn(y0+.1f,.95f)
                    val pixels=IntArray(24*24) { i ->
                        val x=((x0+(x1-x0)*((i%24)+.5f)/24)*rotated.width).toInt().coerceIn(0,rotated.width-1)
                        val y=((y0+(y1-y0)*((i/24)+.5f)/24)*rotated.height).toInt().coerceIn(0,rotated.height-1)
                        rotated.getPixel(x,y)
                    }
                    renderer?.updateLighting(sceneLight.observe(pixels,now))
                }
                texture.alpha=filtered.opacity
                readiness.observe(filtered.accepted && renderer!=null,capturedAt)
                updatePreviewButton()
                // Never carry an old arm mask over a different camera frame.
                arms.update(if(filtered.accepted)rotated else null,if(filtered.accepted)armMask else null)
                displayedPoints=if(filtered.accepted)points else emptyList()
                displayedArmMask=if(filtered.accepted)armMask else null
                fullBodyVisible=PoseAlignment.fullBodyVisible(points)
                val rejection=when {
                    now-capturedAt !in 0..700 -> "late_frame"
                    targetBlocked -> targetReason!!
                    pose!=null && !filtered.accepted -> "motion_reacquiring"
                    world==null -> "image_only_fixture"
                    pose==null && UpperBodyPreview.eligible(points,rotated.width,rotated.height) -> "upper_body_face_forward"
                    else -> turnCalibration.rejectionReason
                }
                diagnostics.observe(now,capturedAt,filtered.accepted,pose?.takeUnless { UpperBodyPreview.isUpper(it) }?.spatial?.errorPixels,rejection,
                    pose?.spatial?.registrationMode ?: "unavailable",timings,pose?.takeUnless { UpperBodyPreview.isUpper(it) }?.spatial?.perspectiveErrorPixels)
                val traceFields=traceDelta.toMutableMap()
                traceFields.putAll(mapOf("model" to selectedDress!!.id,"camera" to if(front)"front" else "back",
                    "source" to projection?.source,"accepted" to filtered.accepted,
                    "display_state" to poseFilter.displayReason(now),
                    "input_age_ms" to now-capturedAt,"registration" to if(pose!=null)"accepted" else rejection,
                    "filter" to poseFilter.decisionReason,"display_safety" to (safetyReason ?: "none"),
                    "visible" to (filtered.pose!=null && renderer!=null),"opacity" to filtered.opacity,
                    "capture_ready" to readiness.ready(now),"yaw_deg" to pose?.spatial?.yawDegrees,
                    "candidate_count" to poseFilter.pendingObservations,"mode" to pose?.spatial?.registrationMode,
                    "target_state" to targetReason,"detected_people" to detectedPeople,"target_index" to targetIndex,
                    "residual_px" to pose?.takeUnless { UpperBodyPreview.isUpper(it) }?.spatial?.errorPixels,"perspective_residual_px" to pose?.takeUnless { UpperBodyPreview.isUpper(it) }?.spatial?.perspectiveErrorPixels,
                    "prepare_ms" to timings?.preparationMs,"pose_ms" to timings?.poseMs,"arms_ms" to timings?.armsMs,
                    "arms_mode" to timings?.armsMode,"arm_mask_used" to (filtered.accepted && armMask!=null),
                    "pose_backend" to timings?.poseBackend,"pose_model" to timings?.poseModel,"confirmed_profile" to pose?.confirmedProfileTurn,
                    "frame_width" to rotated.width,"frame_height" to rotated.height))
                for((joint,key) in listOf(11 to "ls",12 to "rs",23 to "lh",24 to "rh")) {
                    traceFields["image_$key"]=points.getOrNull(joint)?.confidence
                    traceFields["world_$key"]=world?.getOrNull(joint)?.confidence
                }
                if(world!=null && world.size>12) {
                    val axis=world[12].cameraVector()-world[11].cameraVector()
                    if(axis.finite() && axis.length()>1e-5f)
                        traceFields["world_axis_yaw_deg"]=Math.toDegrees(kotlin.math.atan2(-axis.z,axis.x).toDouble())
                }
                trackingTrace.record(now,"frame",traceFields)
                if(diagnosticsLabel.visibility==View.VISIBLE)diagnosticsLabel.text=diagnostics.compact(now)
                updateDress()
                val guidance=PoseGuidance.assess(points,rotated.width,rotated.height,image.width,image.height)
                realignButton.visibility=if(targetReason=="target_lost" && !frozen)View.VISIBLE else View.GONE
                status.text=when {
                    renderer==null -> "This model could not load. Choose another dress."
                    now-capturedAt !in 0..700 -> "Tracking is delayed · Hold still while it catches up"
                    targetReason=="target_centre_required" -> "Stand near the centre · Face forward with both shoulders visible"
                    targetReason=="target_confirming" -> "Finding you · Hold a front view briefly"
                    targetReason=="target_reconfirming" -> "Found your position · Hold still briefly to resume"
                    targetReason=="target_ambiguous" -> "More than one possible target · Keep other people and mirrors out of view"
                    targetReason=="target_lost" -> "Tracking paused · Face forward near the centre"
                    targetBlocked -> "Waiting for fresh tracking · Hold still briefly"
                    pose!=null && filtered.accepted -> when {
                        UpperBodyPreview.isUpper(pose) -> "LIVE · Upper-body preview · Step back to see more of the gown"
                        world!=null && !turnCalibration.ready -> "LIVE · Hold a front view briefly to align"
                        !readiness.ready(now) -> "LIVE · Hold still briefly for a photo"
                        fullBodyVisible -> "LIVE · Turn slowly left or right · Take photo when ready"
                        else -> "LIVE · Upper-body view · Include feet for full length"
                    }
                    rejection=="upper_body_face_forward" -> "Upper-body preview · Face forward and keep both shoulders visible"
                    guidance!=PoseGuidance.Issue.CLEAR -> guidance.message
                    pose==null && filtered.pose!=null -> "Tracking briefly interrupted · Hold your pose"
                    pose==null && world!=null && !turnCalibration.ready -> "LIVE · Face forward briefly to align"
                    pose==null && world!=null -> "LIVE · Turn slightly toward the camera to recover tracking"
                    pose==null -> "Stand upright · Keep shoulders and hips visible"
                    !filtered.accepted -> "LIVE · Re-aligning to your movement…"
                    !readiness.ready(now) -> "Finding your pose…"
                    fullBodyVisible && pose.spatial!=null -> "Ready · Turn gently, arms slightly apart"
                    fullBodyVisible -> "Ready · Face forward, arms slightly apart"
                    else -> "Ready for upper-body preview\nStep back to include the hem"
                }
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!active || dead) return
        if(!frozen && !switchingDress) {
            val now=SystemClock.uptimeMillis()
            val display=poseFilter.displayAt(now)
            texture.alpha=display.opacity
            if(display.pose==null && smoothed!=null) {
                trackingTrace.record(now,"display_expired",mapOf("visible" to false,"filter" to poseFilter.decisionReason,
                    "display_state" to poseFilter.displayReason(now)))
                smoothed=null;renderer?.update(null,1f)
                arms.update(null);displayedPoints=emptyList();displayedArmMask=null
                status.text="Tracking paused · Face the camera with both shoulders visible"
                if(diagnosticsLabel.visibility==View.VISIBLE)diagnosticsLabel.text=diagnostics.compact(now)
            }
        }
        renderer?.render(frameTimeNanos)
        Choreographer.getInstance().postFrameCallback(this)
    }
    override fun onResume() {
        super.onResume(); active=true
        if(frozen) { updateDress();freezeButton.text="Resume live";saveButton.visibility=View.VISIBLE;saveButton.isEnabled=!saved && !saving;refineFrozenArms() }
        updatePreviewButton()
        Choreographer.getInstance().postFrameCallback(this)
    }
    override fun onPause() {
        trackingTrace.record(SystemClock.uptimeMillis(),"paused")
        active=false;previewEpoch++;refiningPreview=false
        captureHelpDialog?.dismiss();captureHelpDialog=null
        diagnosticsDialog?.dismiss();diagnosticsDialog=null
        dressPicker?.dismiss()
        dressLoadGeneration++
        renderer?.cancelDressLoad()
        if(::changeDressButton.isInitialized)setDressLoading(false)
        if(::freezeButton.isInitialized)cancelCountdown()
        Choreographer.getInstance().removeFrameCallback(this)
        renderer?.update(null,1f)
        if(!frozen) { resetTracking();hasLiveFrame=false }
        super.onPause()
    }
    override fun onDestroy() {
        if(!isChangingConfigurations)generatedDress?.let { GeneratedDressFile.remove(this,it.asset) }
        dead=true; active=false
        if(::freezeButton.isInitialized) cancelCountdown()
        Choreographer.getInstance().removeFrameCallback(this)
        provider?.unbindAll()
        worker.execute { detector?.close(); detector=null;armSegmenter?.close();armSegmenter=null }
        worker.shutdown()
        modelReader.shutdownNow()
        traceWriter.shutdown()
        trackingTrace.clear();pendingTraceExport=null
        renderer?.close(); renderer=null
        if(::image.isInitialized) image.setImageDrawable(null)
        if(::arms.isInitialized)arms.update(null)
        super.onDestroy()
    }
}
