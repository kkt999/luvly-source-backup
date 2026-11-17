package com.luvly.luvly_app.ar

import android.graphics.*
import android.os.*
import android.view.*
import android.widget.Button
import java.io.File

/** Debug-only end-to-end customer flow. No camera, permissions or personal images. */
class TryOnFlowFixtureActivity: TryOnActivity() {
    override fun accountLookStore() = LookStore(java.io.File(noBackupFilesDir, "ar_looks"))
    private val handler=Handler(Looper.getMainLooper())
    private var alive=true
    private val before=mutableSetOf<String>()
    private var actionsStartedAt=0L
    private var timerStartedWithoutPose=false
    private var usedSpatialRegistration=false
    private var enabledSamples=0
    private var disabledAfterFirstFrame=0
    private val slowFrames get()=intent.getBooleanExtra("fixtureSlowFrames",false)
    override fun onCreate(savedInstanceState: Bundle?) {
        val model=ArDressCatalogue.byId(intent.getStringExtra("fixtureDress") ?: "princess-wedding")!!
        if(intent.getBooleanExtra("fixtureGenerated",false)) {
            val buffer=DressRenderer.readModel(this,model.asset)
            val bytes=ByteArray(buffer.remaining()).also { buffer.get(it) }
            intent.putExtras(GeneratedDressFile.stage(this,"fixture-gown","Generated test gown",bytes))
        } else {
            intent.putExtra("dressId",model.id)
            intent.putExtra("modelAsset",model.asset)
        }
        super.onCreate(savedInstanceState)
    }
    override fun beginCameraExperience() {
        setFixturePhotoDelay(if(intent.getBooleanExtra("fixtureInstant",false))0 else 10)
        val store=LookStore(File(noBackupFilesDir,"ar_looks"))
        before.addAll(store.list().map { it.id })
        val bitmap=Bitmap.createBitmap(600,900,Bitmap.Config.ARGB_8888)
        val c=Canvas(bitmap);c.drawColor(Color.rgb(226,230,232))
        val p=Paint(Paint.ANTI_ALIAS_FLAG).apply { color=Color.rgb(55,125,132) }
        c.drawOval(258f,65f,342f,175f,p)
        c.drawRect(278f,155f,322f,215f,p)
        c.drawRoundRect(180f,215f,420f,485f,25f,25f,p)
        p.strokeWidth=40f;p.strokeCap=Paint.Cap.ROUND
        c.drawLine(180f,245f,150f,590f,p);c.drawLine(420f,245f,450f,590f,p)
        if(intent.getBooleanExtra("fixtureArms",false)) {
            p.color=Color.rgb(204,115,60)
            c.drawLine(192f,450f,312f,432f,p)
            c.drawCircle(332f,432f,22f,p)
        }
        c.drawLine(250f,460f,250f,845f,p);c.drawLine(350f,460f,350f,845f,p)
        p.color=Color.DKGRAY;p.textSize=18f
        c.drawText("Synthetic test · not a person or fit result",100f,35f,p)
        val points=MutableList(33){BodyPoint(.5f,.5f,1f)}
        points[0]=BodyPoint(.5f,.13f,1f)
        points[11]=BodyPoint(.3f,.25f,1f);points[12]=BodyPoint(.7f,.25f,1f)
        points[23]=BodyPoint(.4f,.50f,1f);points[24]=BodyPoint(.6f,.50f,1f)
        if(intent.getBooleanExtra("fixtureArms",false)) {
            for(i in listOf(11,12,23,24))points[i]=points[i].copy(z=0f)
            points[13]=BodyPoint(.32f,.5f,1f,-.15f);points[15]=BodyPoint(.52f,.48f,1f,-.2f)
            points[17]=BodyPoint(.57f,.46f,1f,-.2f);points[19]=BodyPoint(.57f,.50f,1f,-.2f)
        }
        for(i in listOf(27,28,31,32))points[i]=BodyPoint(if(i%2==0).58f else .42f,.94f,1f)
        val projection=FrameProjection(600,900,900f,900f,source="synthetic-known-lens")
        val world=points.map { WorldBodyPoint((it.x-.5f)*600*1.5f/900,
            (it.y-.5f)*900*1.5f/900,0f,1f) }
        // Deterministic synthetic segmentation tests compositing, not model accuracy.
        val alpha=if(intent.getBooleanExtra("fixtureArms",false)) {
            val values=FloatArray(600*900) { i ->
                if(bitmap.getPixel(i%600,i/600)==Color.rgb(204,115,60))1f else 0f
            }
            val pixels=ArmSkinMask.pixels(SkinConfidence(600,900,values),points,600,900)!!
            Bitmap.createBitmap(pixels,600,900,Bitmap.Config.ARGB_8888)
        } else null
        handler.post(object: Runnable {
            override fun run() {
                if(!alive)return
                val elapsed=SystemClock.uptimeMillis()-actionsStartedAt
                val dropout=intent.getBooleanExtra("fixtureDropout",false) &&
                    actionsStartedAt>0 && elapsed in 11500..12600
                val noPose=intent.getBooleanExtra("fixtureNoPose",false) ||
                    (intent.getBooleanExtra("fixtureStepBack",false) && (actionsStartedAt==0L || elapsed<7000))
                val capturedAt=SystemClock.uptimeMillis()-(if(slowFrames)450L else 0L)
                displayCameraFrame(bitmap,if(dropout || noPose) emptyList() else points,capturedAt,armMask=alpha,
                    world=if(dropout || noPose)emptyList() else world,projection=projection)
                if(spatialPoseProbe()!=null)usedSpatialRegistration=true
                handler.postDelayed(this,if(slowFrames)500 else 100)
            }
        })
        handler.post(object: Runnable {
            override fun run() {
                if(!alive)return
                if(!window.decorView.hasWindowFocus() || window.decorView.width<=0) {
                    handler.postDelayed(this,500);return
                }
                exerciseActions(store)
            }
        })
    }
    private fun exerciseActions(store: LookStore) {
        actionsStartedAt=SystemClock.uptimeMillis()
        if(slowFrames)handler.post(object: Runnable {
            override fun run() {
                if(!alive || SystemClock.uptimeMillis()-actionsStartedAt>=2150)return
                if(button("Take photo")?.isEnabled==true)enabledSamples++
                else if(enabledSamples>0)disabledAfterFirstFrame++
                handler.postDelayed(this,50)
            }
        })
        handler.postDelayed({
            val preview=button("Take photo")
            timerStartedWithoutPose=preview?.isEnabled==true && intent.getBooleanExtra("fixtureStepBack",false)
            preview?.performClick()
        },2200)
        if(intent.getBooleanExtra("fixtureCancel",false))
            handler.postDelayed({ button("Cancel timer")?.performClick() },4000)
        handler.postDelayed({ captureWindow("ar_flow_preview.png") },13000)
        if(!slowFrames)handler.postDelayed({ button("Save look")?.performClick() },17500)
        handler.postDelayed({
            val made=store.list().filter { it.id !in before }
            File(filesDir,"ar_flow_result.txt").writeText("Model: ${intent.getStringExtra("dressId")}\nDropout: ${intent.getBooleanExtra("fixtureDropout",false)}\nStep back: ${intent.getBooleanExtra("fixtureStepBack",false)}\nTimer allowed before pose: $timerStartedWithoutPose\nNo pose: ${intent.getBooleanExtra("fixtureNoPose",false)}\nCancel: ${intent.getBooleanExtra("fixtureCancel",false)}\nArms: ${intent.getBooleanExtra("fixtureArms",false)}\nCompleted: ${System.currentTimeMillis()}\nSaved new looks: ${made.size}\n")
            File(filesDir,"ar_flow_result.txt").appendText("Spatial registration: $usedSpatialRegistration\n")
            if(slowFrames)File(filesDir,"ar_flow_result.txt").appendText(
                "Slow camera frames · Build ${com.luvly.luvly_app.BuildConfig.VERSION_CODE}\n"+
                    "Enabled samples: $enabledSamples\nDisabled between frames: $disabledAfterFirstFrame\n"+
                    "Photo frozen: ${button("Resume live")?.isEnabled==true}\n")
            // Preserve QA evidence separately, not as a fake customer album entry.
            made.singleOrNull()?.let {
                File(it.path).copyTo(File(filesDir,"ar_flow_saved.png"),overwrite=true)
                val removed=store.delete(it.id)
                File(filesDir,"ar_flow_result.txt").appendText("Synthetic entry removed: $removed\n")
            }
            captureWindow("ar_flow_saved_ui.png")
        },22000)
    }
    private fun button(label: String, view: View=window.decorView): Button? {
        if(view is Button && view.text.toString()==label)return view
        if(view is ViewGroup)for(i in 0 until view.childCount)button(label,view.getChildAt(i))?.let { return it }
        return null
    }
    private fun captureWindow(name: String) {
        if(!alive)return
        val view=window.decorView
        if(view.width<=0 || view.height<=0 || !view.hasWindowFocus())return
        val bitmap=Bitmap.createBitmap(view.width,view.height,Bitmap.Config.ARGB_8888)
        try { PixelCopy.request(window,bitmap,{ result ->
            if(result==PixelCopy.SUCCESS)File(filesDir,name).outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG,100,it)
            }
            bitmap.recycle()
        },handler) } catch(_:IllegalArgumentException) { bitmap.recycle() }
    }
    override fun onDestroy() {
        alive=false;handler.removeCallbacksAndMessages(null);super.onDestroy()
    }
}
