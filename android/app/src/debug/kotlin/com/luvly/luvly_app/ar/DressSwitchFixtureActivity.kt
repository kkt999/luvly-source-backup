package com.luvly.luvly_app.ar

import android.graphics.*
import android.os.*
import android.view.*
import android.widget.*
import java.io.File
import java.util.concurrent.Executors

/** Exercises production picker/loading with synthetic frames. Never opens the camera or user album. */
class DressSwitchFixtureActivity: TryOnActivity() {
    private val handler=Handler(Looper.getMainLooper())
    private val writer=Executors.newSingleThreadExecutor()
    private var alive=true
    private var failNext=false
    private var slowNext=false
    private var originalRenderer: DressRenderer?=null
    private val checks=mutableListOf<String>()
    private val store by lazy { LookStore(File(noBackupFilesDir,"ar_switch_fixture_looks")) }
    override fun accountLookStore()=store
    override fun readDressModel(dress: ArDress): java.nio.ByteBuffer {
        if(failNext) { failNext=false;throw java.io.IOException("Synthetic read failure") }
        if(slowNext) { slowNext=false;Thread.sleep(600) }
        return super.readDressModel(dress)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        val initial=ArDressCatalogue.byId("elegant-local-review")!!
        intent.putExtra("dressId",initial.id);intent.putExtra("modelAsset",initial.asset)
        super.onCreate(savedInstanceState)
    }
    override fun beginCameraExperience() {
        setFixturePhotoDelay(10)
        val bitmap=Bitmap.createBitmap(600,900,Bitmap.Config.ARGB_8888)
        Canvas(bitmap).apply {
            drawColor(Color.rgb(226,230,232))
            val paint=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.rgb(55,125,132) }
            drawOval(258f,65f,342f,175f,paint);drawRoundRect(180f,215f,420f,485f,25f,25f,paint)
            paint.color=Color.DKGRAY;paint.textSize=18f
            drawText("Synthetic dress-switch test · no camera",85f,35f,paint)
        }
        val points=MutableList(33){BodyPoint(.5f,.5f,1f)}.apply {
            this[0]=BodyPoint(.5f,.13f,1f)
            this[11]=BodyPoint(.3f,.25f,1f);this[12]=BodyPoint(.7f,.25f,1f)
            this[23]=BodyPoint(.4f,.5f,1f);this[24]=BodyPoint(.6f,.5f,1f)
            for(i in listOf(27,28,31,32))this[i]=BodyPoint(if(i%2==0).6f else .4f,.94f,1f)
        }
        val world=points.map { WorldBodyPoint((it.x-.5f)*1.2f,(it.y-.5f)*1.8f,0f,1f) }
        handler.post(object:Runnable {
            override fun run() {
                if(!alive)return
                displayCameraFrame(bitmap,points,world=world,projection=FrameProjection(600,900,900f,900f))
                handler.postDelayed(this,100)
            }
        })
        later(2200) { startChecks() }
    }
    private fun later(ms: Long,run:()->Unit) { handler.postDelayed({ if(alive)run() },ms) }
    private fun record(label: String,pass: Boolean) { checks.add("${if(pass)"PASS" else "FAIL"} $label") }
    private fun nodes(root:View): List<View> = listOf(root)+if(root is ViewGroup)
        (0 until root.childCount).flatMap { nodes(root.getChildAt(it)) } else emptyList()
    private fun button(label:String,root:View=window.decorView)=nodes(root).filterIsInstance<Button>().firstOrNull { it.text.toString()==label }
    private fun openPicker():View? {
        button("Change dress")?.performClick()
        return dressPickerWindow()?.decorView
    }
    private fun row(root:View,dress:ArDress)=nodes(root).firstOrNull { it.contentDescription?.startsWith("${dress.name}.")==true }
    private fun startChecks() {
        originalRenderer=dressSwitchProbe().third
        val current=dressSwitchProbe().first
        val root=openPicker()
        record("picker opens",root!=null)
        if(root==null) { report();return }
        val images=nodes(root).filterIsInstance<ImageView>()
        record("all three dress photos decoded",images.size==3 && images.all { it.drawable is android.graphics.drawable.BitmapDrawable })
        record("current dress cannot be redundantly loaded",button("Currently trying on",root)?.isEnabled==false)
        val princess=ArDressCatalogue.byId("princess-wedding")!!
        row(root,princess)?.performClick()
        record("selecting a photo does not load until confirmed",dressSwitchProbe().first==current && !dressSwitchProbe().second)
        later(400) {
            capture("ar_switch_picker.png",dressPickerWindow()!!)
            button("Close",root)?.performClick()
            record("cancel keeps current dress",dressSwitchProbe().first==current)
            switchDress(ArDressCatalogue.byId(current)!!)
            record("same dress is a no-op",!dressSwitchProbe().second && dressSwitchProbe().third===originalRenderer)
            switchRound(0)
        }
    }
    private fun switchRound(round:Int) {
        if(round==9) { gpuCancellationCheck();return }
        val next=ArDressCatalogue.byId(listOf("princess-wedding","francine-reference","elegant-local-review")[round%3])!!
        val root=openPicker()
        if(root==null) { record("picker round $round",false);report();return }
        row(root,next)?.performClick()
        button("Try ${next.name}",root)?.performClick()
        record("loading guards round $round",dressSwitchProbe().second && button("Loading…")?.isEnabled==false && button("Take photo")?.isEnabled==false)
        switchDress(ArDressCatalogue.all().first { it.id!=next.id }) // Ignored while loading.
        awaitLoad {
            later(1200) {
                record("switch $round to ${next.id}",dressSwitchProbe().first==next.id && dressSwitchProbe().third===originalRenderer)
                record("rendered and tracked after switch $round",trackingDisplayProbe().first && overlayVisible())
                if(round==0)capture("ar_switch_princess.png",window)
                switchRound(round+1)
            }
        }
    }
    private fun gpuCancellationCheck() {
        val renderer=dressSwitchProbe().third!!
        var notified=false
        val next=ArDressCatalogue.byId("princess-wedding")!!
        renderer.loadDress(DressRenderer.readModel(this,next.asset),next.anchors) { notified=true }
        renderer.cancelDressLoad()
        record("pending GPU load cancelled without committing",!notified && dressSwitchProbe().first=="elegant-local-review")
        later(1200) {
            record("old model still renders after cancelled load",overlayVisible())
            failureCheck()
        }
    }
    private fun failureCheck() {
        val previous=dressSwitchProbe().first
        failNext=true
        switchDress(ArDressCatalogue.byId("princess-wedding")!!)
        awaitLoad {
            record("read failure keeps old dress and renderer",dressSwitchProbe().first==previous && dressSwitchProbe().third===originalRenderer)
            slowNext=true
            switchDress(ArDressCatalogue.byId("princess-wedding")!!)
            // Same lifecycle callbacks as backgrounding, while local file IO is pending.
            onPause()
            later(900) {
                onResume()
                record("pause rejects late file load",dressSwitchProbe().first==previous && !dressSwitchProbe().second)
                later(1400) { previewCheck() }
            }
        }
    }
    private fun previewCheck() {
        val preview=button("Take photo")
        record("preview enabled after repeated switches",preview?.isEnabled==true)
        preview?.performClick()
        later(11500) {
            record("countdown still creates a frozen preview",button("Resume live")!=null)
            val root=openPicker()
            root?.let { button("Close",it)?.performClick() }
            record("cancel preserves frozen preview",button("Resume live")!=null)
            val before=store.list().map { it.id }.toSet()
            button("Save look")?.performClick()
            later(2200) {
                val made=store.list().filter { it.id !in before }
                record("save works after switching",made.size==1)
                made.forEach { store.delete(it.id) }
                capture("ar_switch_saved_ui.png",window)
                awaitSaveUi { switchAfterSavedPreview() }
            }
        }
    }
    private fun awaitSaveUi(done:()->Unit) {
        val start=SystemClock.uptimeMillis()
        fun poll() {
            if(button("Change dress")?.isEnabled==true)done()
            else if(SystemClock.uptimeMillis()-start>8000) { record("save UI completion timeout",false);report() }
            else later(100) { poll() }
        }
        poll()
    }
    private fun switchAfterSavedPreview() {
        val next=ArDressCatalogue.byId("princess-wedding")!!
        val root=openPicker()
        record("picker opens from frozen saved preview",root!=null)
        if(root==null) { report();return }
        row(root,next)?.performClick()
        button("Try ${next.name}",root)?.performClick()
        awaitLoad {
            later(1200) {
                val state=dressSwitchProbe()
                record("switch from frozen preview selected ${state.first}",state.first==next.id && !state.second)
                record("switch from frozen preview button ${nodes(window.decorView).filterIsInstance<Button>().map { "${it.text}:${it.isEnabled}" }}",button("Take photo")?.isEnabled==true)
                record("switch from frozen preview overlay ${trackingDisplayProbe()}",overlayVisible())
                capture("ar_switch_after_frozen.png",window)
                report()
            }
        }
    }
    private fun awaitLoad(done:()->Unit) {
        val start=SystemClock.uptimeMillis()
        fun poll() {
            if(!dressSwitchProbe().second)done()
            else if(SystemClock.uptimeMillis()-start>23000) { record("load timeout",false);report() }
            else later(100) { poll() }
        }
        later(100) { poll() }
    }
    private fun overlayVisible():Boolean {
        val texture=nodes(window.decorView).filterIsInstance<TextureView>().firstOrNull() ?: return false
        val bitmap=texture.bitmap ?: return false
        val found=(0 until bitmap.height step 30).any { y -> (0 until bitmap.width step 30).any { x -> Color.alpha(bitmap.getPixel(x,y))>32 } }
        bitmap.recycle();return found && texture.alpha>.9f
    }
    private fun capture(name:String,target:Window) {
        val v=target.decorView
        if(v.width<=0 || v.height<=0)return
        val bitmap=Bitmap.createBitmap(v.width,v.height,Bitmap.Config.ARGB_8888)
        PixelCopy.request(target,bitmap,{ result ->
            writer.execute {
                try { if(result==PixelCopy.SUCCESS)File(filesDir,name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG,100,it) } }
                finally { bitmap.recycle() }
            }
        },handler)
    }
    private fun report() {
        val result="Completed: ${System.currentTimeMillis()}\nSynthetic frames; real GPU and picker; no customer data\n"+checks.joinToString("\n")
        writer.execute { File(filesDir,"ar_switch_result.txt").writeText(result) }
    }
    override fun onDestroy() {
        alive=false;handler.removeCallbacksAndMessages(null);writer.shutdown();super.onDestroy()
    }
}
