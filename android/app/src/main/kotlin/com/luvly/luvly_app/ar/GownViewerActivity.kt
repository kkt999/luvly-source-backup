package com.luvly.luvly_app.ar

import android.app.Activity
import android.app.AlertDialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.*
import android.widget.*
import com.google.firebase.auth.FirebaseAuth
import java.util.concurrent.Executors

/** Local orbit view with a separate Chrome WebXR room-AR action. */
open class GownViewerActivity: Activity(), Choreographer.FrameCallback {
    private val worker=Executors.newSingleThreadExecutor()
    private var generation=0
    private var active=false
    private var closed=false
    private var renderer: GownViewerRenderer?=null
    protected lateinit var texture: TextureView
    private lateinit var status: TextView
    private lateinit var retry: Button
    private lateinit var loading: ProgressBar
    private lateinit var dress: ArDress
    private val buttons=mutableListOf<Button>()
    private val rose=Color.rgb(164,80,100)
    private val ink=Color.rgb(51,43,46)
    private val authListener=FirebaseAuth.AuthStateListener { if(!canOpen())finish() }
    protected open fun canOpen()=FirebaseAuth.getInstance().currentUser!=null
    protected open fun onModelReady() {}
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val chosen=ArDressCatalogue.resolve(intent.getStringExtra("dressId"),intent.getStringExtra("modelAsset"))
        val info=chosen?.let { GownViewerModels.info(it) }
        if(!canOpen() || chosen==null || info==null) { finish();return }
        dress=chosen
        window.statusBarColor=Color.rgb(255,251,249)
        window.navigationBarColor=Color.rgb(255,251,249)
        window.decorView.systemUiVisibility=View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        val page=LinearLayout(this).apply {
            orientation=LinearLayout.VERTICAL;setBackgroundColor(Color.rgb(255,251,249))
            setPadding(dp(16),0,dp(16),dp(8))
            setOnApplyWindowInsetsListener { v,insets ->
                v.setPadding(dp(16),insets.systemWindowInsetTop,dp(16),insets.systemWindowInsetBottom+dp(8));insets
            }
        }
        val header=LinearLayout(this).apply { gravity=Gravity.CENTER_VERTICAL }
        header.addView(button("Back") { finish() },LinearLayout.LayoutParams(dp(76),dp(48)))
        header.addView(label("360° view",20f).apply {gravity=Gravity.CENTER},LinearLayout.LayoutParams(0,dp(52),1f))
        header.addView(button("About") {
            AlertDialog.Builder(this).setTitle("About this model")
                .setMessage(info.about+"\n\n360° mode works locally without a camera."+
                    if(info.roomAvailable) " View in your space opens Chrome WebXR and downloads a static reference model. On supported Android phones, Chrome uses Google Play Services for AR. Its room scale is illustrative." else "")
                .setPositiveButton("Done",null).show()
        },LinearLayout.LayoutParams(dp(76),dp(48)))
        page.addView(header)
        page.addView(label(info.title,22f))
        page.addView(label("3D reference · No camera needed",13f))
        val stage=FrameLayout(this).apply {
            background=GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(Color.rgb(100,112,124),Color.rgb(150,160,170))).apply {cornerRadius=dp(20).toFloat()}
            clipToOutline=true
        }
        texture=TextureView(this).apply { contentDescription="${info.title} 3D model. Drag to rotate, pinch to zoom. View buttons are below." }
        stage.addView(texture,FrameLayout.LayoutParams(-1,-1))
        loading=ProgressBar(this)
        stage.addView(loading,FrameLayout.LayoutParams(dp(40),dp(40),Gravity.CENTER))
        page.addView(stage,LinearLayout.LayoutParams(-1,0,1f).apply {topMargin=dp(12);bottomMargin=dp(8)})
        status=label("Loading your 3D view…",14f).apply { gravity=Gravity.CENTER;accessibilityLiveRegion=View.ACCESSIBILITY_LIVE_REGION_POLITE }
        page.addView(status)
        retry=button("Retry") { load() }.apply { visibility=View.GONE }
        page.addView(retry)
        val controlScroll=ScrollView(this).apply { isFillViewport=true }
        val controls=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL }
        if(info.roomAvailable) {
        val space=button("View in your space") { openRoomAr() }.apply {
            setTextColor(Color.WHITE)
            background=GradientDrawable().apply {setColor(rose);cornerRadius=dp(12).toFloat()}
        }
        // Room AR loads its own static model. A local Filament load failure
        // must not disable this independent action.
        controls.addView(space,LinearLayout.LayoutParams(-1,dp(48)).apply {setMargins(dp(3),dp(3),dp(3),dp(3))})
        }
        val views=LinearLayout(this)
        for(name in listOf("Front","Back view","Reset")) {
            val control=button(name) { selectView(name) };buttons.add(control)
            views.addView(control,LinearLayout.LayoutParams(0,dp(48),1f).apply {setMargins(dp(3),dp(3),dp(3),dp(3))})
        }
        controls.addView(views)
        val zooms=LinearLayout(this)
        for((name,factor) in listOf("Zoom out" to .8,"Zoom in" to 1.25)) {
            val control=button(name) { zoomBy(factor) };buttons.add(control)
            zooms.addView(control,LinearLayout.LayoutParams(0,dp(48),1f).apply {setMargins(dp(3),dp(3),dp(3),dp(3))})
        }
        controls.addView(zooms)
        controls.addView(label("Drag to rotate · Pinch to zoom · Double-tap to reset",12f).apply { gravity=Gravity.CENTER })
        controlScroll.addView(controls)
        page.addView(controlScroll,LinearLayout.LayoutParams(-1,dp(if(info.roomAvailable)192 else 140)))
        setContentView(page);page.requestApplyInsets()
        val scale=ScaleGestureDetector(this,object: ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScale(detector: ScaleGestureDetector): Boolean { zoomBy(detector.scaleFactor.toDouble());return true }
        })
        val drag=GestureDetector(this,object: GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: android.view.MotionEvent)=true
            override fun onScroll(e1: android.view.MotionEvent?,e2: android.view.MotionEvent,dx: Float,dy: Float): Boolean {
                if(!scale.isInProgress && e2.pointerCount==1) {
                    renderer?.orbit?.drag(-dx/texture.width.coerceAtLeast(1)*360.0,-dy/texture.height.coerceAtLeast(1)*100.0)
                    renderer?.updateCamera()
                };return true
            }
            override fun onDoubleTap(e: android.view.MotionEvent): Boolean { selectView("Reset");return true }
        })
        texture.setOnTouchListener { _,event -> scale.onTouchEvent(event);drag.onTouchEvent(event);true }
        FirebaseAuth.getInstance().addAuthStateListener(authListener)
        load()
    }
    protected fun selectView(name: String) {
        renderer?.let { when(name){"Front"->it.orbit.front();"Back view"->it.orbit.back();else->it.orbit.reset()};it.updateCamera() }
    }
    protected fun zoomBy(factor: Double) { renderer?.let { it.orbit.scale(factor);it.updateCamera() } }
    protected fun cameraState(): DoubleArray = renderer?.orbit?.let { doubleArrayOf(it.yaw,it.pitch,it.zoom) } ?: doubleArrayOf()
    private fun openRoomAr() {
        if(!canOpen())return
        launchRoomAr()
    }
    private fun launchRoomAr() {
        if(!canOpen())return
        try {
            val uri=Uri.parse(RoomArLink.webXr(dress.id))
            val browser=Intent(Intent.ACTION_VIEW,uri)
                .putExtra("com.android.browser.application_id",packageName)
            try {
                startActivity(browser.setPackage(RoomArLink.BROWSER_PACKAGE))
            } catch(_:ActivityNotFoundException) {
                startActivity(browser.setPackage(null))
            }
        } catch(_:ActivityNotFoundException) { showArSetup() }
          catch(_:SecurityException) { showArSetup() }
          catch(_:IllegalArgumentException) {
            AlertDialog.Builder(this).setTitle("Room AR is unavailable")
                .setMessage("The reference model could not be opened. You can continue exploring it in 360°.")
                .setPositiveButton("Back to 360°",null).show()
        }
    }
    private fun showArSetup() {
        AlertDialog.Builder(this).setTitle("Open room AR in Chrome")
            .setMessage("Room viewing needs a browser. Install or update Chrome to use WebXR on an AR-supported Android phone. Your 360° view is still available here.")
            .setNegativeButton("Back to 360°",null)
            .setPositiveButton("Open Google Play") { _,_ ->
                try {
                    startActivity(Intent(Intent.ACTION_VIEW,Uri.parse("https://play.google.com/store/apps/details?id=com.android.chrome")))
                } catch(_:ActivityNotFoundException) {
                    Toast.makeText(this,"Open Google Play and search for Google Chrome.",Toast.LENGTH_LONG).show()
                }
            }.show()
    }
    private fun load() {
        val attempt=++generation
        buttons.forEach { it.isEnabled=false };retry.visibility=View.GONE;loading.visibility=View.VISIBLE
        status.text="Loading your 3D view…"
        worker.execute {
            val buffer=runCatching { DressRenderer.readModel(this,dress.asset) }
            runOnUiThread {
                if(closed || isFinishing || attempt!=generation)return@runOnUiThread
                try {
                    renderer?.close();renderer=null
                    renderer=GownViewerRenderer(texture,GownViewerModels.info(dress)!!.initialZoom)
                    renderer!!.load(buffer.getOrThrow())
                    buttons.forEach { it.isEnabled=true }
                    status.text="Explore the neckline, skirt and train"
                    onModelReady()
                } catch(_:Exception) {
                    renderer?.close();renderer=null
                    status.text="Could not load the 3D view. Please try again."
                    retry.visibility=View.VISIBLE
                } finally { loading.visibility=View.GONE }
            }
        }
    }
    override fun onResume() {
        super.onResume();if(!canOpen()){finish();return}
        active=true;Choreographer.getInstance().postFrameCallback(this)
    }
    override fun onPause() { active=false;Choreographer.getInstance().removeFrameCallback(this);super.onPause() }
    override fun doFrame(time: Long) {
        if(!active || closed)return
        renderer?.render(time);Choreographer.getInstance().postFrameCallback(this)
    }
    override fun onDestroy() {
        closed=true;generation++;active=false;Choreographer.getInstance().removeFrameCallback(this)
        FirebaseAuth.getInstance().removeAuthStateListener(authListener)
        worker.shutdownNow();renderer?.close();renderer=null;super.onDestroy()
    }
    private fun label(text: String,size: Float)=TextView(this).apply {
        this.text=text;textSize=size;setTextColor(ink);setPadding(dp(4),dp(4),dp(4),dp(4));gravity=Gravity.CENTER_VERTICAL
    }
    private fun button(text: String,action: ()->Unit)=Button(this).apply {
        this.text=text;isAllCaps=false;textSize=14f;setTextColor(rose)
        background=GradientDrawable().apply {setColor(Color.rgb(255,251,249));setStroke(dp(1),Color.rgb(230,211,216));cornerRadius=dp(12).toFloat()}
        setOnClickListener { action() }
    }
    private fun dp(value: Int)=(value*resources.displayMetrics.density).toInt()
}
