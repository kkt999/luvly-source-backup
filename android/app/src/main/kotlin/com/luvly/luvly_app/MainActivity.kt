package com.luvly.luvly_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import com.luvly.luvly_app.ar.TryOnActivity
import com.luvly.luvly_app.ar.GownViewerActivity
import com.luvly.luvly_app.ar.GownViewerModels
import com.luvly.luvly_app.ar.GeneratedDressFile
import com.luvly.luvly_app.ar.ArDressCatalogue
import com.luvly.luvly_app.ar.LookStore
import com.luvly.luvly_app.ar.AccountLookDirectory
import com.luvly.luvly_app.makeup.BridalMakeupActivity
import com.google.firebase.auth.FirebaseAuth
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private var receiptSaver: ReceiptSaver? = null
    private var scanReply: MethodChannel.Result? = null
    private var scanOwner: String? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        receiptSaver=ReceiptSaver(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "luvly/makeup")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent(this, BridalMakeupActivity::class.java))
                    result.success(null)
                } catch (_: android.content.ActivityNotFoundException) {
                    result.error("MAKEUP_UNAVAILABLE", "Could not open bridal makeup preview", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"luvly/body-scan")
            .setMethodCallHandler { call,result->
                if(call.method!="scan" && call.method!="estimateMeasurements"){
                    result.notImplemented();return@setMethodCallHandler
                }
                val height=if(call.method=="estimateMeasurements")call.argument<Number>("heightCm")?.toDouble() else null
                if(call.method=="estimateMeasurements" && (height==null || height !in 120.0..220.0)){
                    result.error("SCAN_HEIGHT","Enter a height from 120 to 220 cm",null);return@setMethodCallHandler
                }
                val uid=FirebaseAuth.getInstance().currentUser?.uid
                if(uid==null){result.error("AUTH_REQUIRED","Sign in before scanning",null);return@setMethodCallHandler}
                if(scanReply!=null){result.error("SCAN_BUSY","A scan is already open",null);return@setMethodCallHandler}
                scanReply=result;scanOwner=uid
                try {
                    val intent=Intent(this,com.luvly.luvly_app.ar.BodyScanActivity::class.java)
                    if(height!=null)intent.putExtra("heightCm",height)
                    startActivityForResult(intent,7821)
                }
                catch(_:Exception){scanReply=null;scanOwner=null;result.error("SCAN_UNAVAILABLE","Could not open body scanning",null)}
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"luvly/receipts")
            .setMethodCallHandler {call,result->if(call.method=="save")receiptSaver?.save(call,result) else result.notImplemented()}
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "luvly/ar")
            .setMethodCallHandler { call, result ->
                val uid = FirebaseAuth.getInstance().currentUser?.uid
                if (uid == null) {
                    result.error("AUTH_REQUIRED", "Sign in to use try-on and saved looks", null)
                    return@setMethodCallHandler
                }
                val store=LookStore(AccountLookDirectory.forUid(noBackupFilesDir, uid))
                if(call.method=="listLooks") {
                    result.success(store.list().map { it.toMap() });return@setMethodCallHandler
                }
                if(call.method=="deleteLook") {
                    try { result.success(store.delete(call.argument<String>("id") ?: "")) }
                    catch(_:Exception) { result.error("LOOK_DELETE","Could not delete this look",null) }
                    return@setMethodCallHandler
                }
                if(call.method=="openGeneratedTryOn") {
                    val id=call.argument<String>("dressId")
                    val label=call.argument<String>("label")
                    val bytes=call.argument<ByteArray>("model")
                    thread(name="luvly-generated-gown") {
                        val staged=runCatching { GeneratedDressFile.stage(this,id,label,bytes) }
                        runOnUiThread {
                            val intent=staged.getOrNull()
                            if(intent==null) {
                                result.error("AR_UNAVAILABLE","Could not open this 3D model",null)
                            } else if(isDestroyed || isFinishing || FirebaseAuth.getInstance().currentUser?.uid!=uid) {
                                GeneratedDressFile.remove(this,intent.getStringExtra("generatedModel")!!)
                                result.error("AR_UNAVAILABLE","Try-on session changed",null)
                            } else {
                                try {
                                    startActivity(intent)
                                    result.success(null)
                                } catch (_: Exception) {
                                    GeneratedDressFile.remove(this,intent.getStringExtra("generatedModel")!!)
                                    result.error("AR_START","Unable to open live try-on",null)
                                }
                            }
                        }
                    }
                    return@setMethodCallHandler
                }
                if (call.method == "openTryOn" || call.method == "openGownViewer") {
                    val dress=ArDressCatalogue.resolve(call.argument<String>("dressId"),call.argument<String>("modelAsset"))
                    if(dress==null || (call.method=="openGownViewer" && GownViewerModels.info(dress)==null)) {
                        result.error("AR_UNAVAILABLE","No AR model is available for the selected dress",null)
                        return@setMethodCallHandler
                    }
                    try {
                        val target=if(call.method=="openGownViewer")GownViewerActivity::class.java else TryOnActivity::class.java
                        startActivity(Intent(this, target)
                            .putExtra("dressId",dress.id).putExtra("modelAsset",dress.asset))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("AR_START", "Unable to open live try-on", null)
                    }
                } else result.notImplemented()
            }
    }
    override fun onActivityResult(requestCode: Int,resultCode: Int,data: Intent?) {
        if(requestCode==7821){
            val reply=scanReply;val owner=scanOwner;scanReply=null;scanOwner=null
            if(owner==null || owner!=FirebaseAuth.getInstance().currentUser?.uid)reply?.error("AUTH_REQUIRED","Your account changed during the scan",null)
            else if(resultCode!=android.app.Activity.RESULT_OK || data==null)reply?.success(null)
            else if(data.getBooleanExtra("measurementEstimate",false))reply?.success(mapOf(
                "Bust" to data.getDoubleExtra("bustCm",Double.NaN),
                "Waist" to data.getDoubleExtra("waistCm",Double.NaN),
                "Hips" to data.getDoubleExtra("hipsCm",Double.NaN)))
            else reply?.success(mapOf("algorithmVersion" to data.getStringExtra("algorithmVersion"),
                "shoulderHipRatio" to data.getDoubleExtra("shoulderHipRatio",Double.NaN),
                "torsoShoulderRatio" to data.getDoubleExtra("torsoShoulderRatio",Double.NaN),
                "sampleCount" to data.getIntExtra("sampleCount",0),"durationMs" to data.getLongExtra("durationMs",0),
                "relativeSpread" to data.getDoubleExtra("relativeSpread",Double.NaN),"capturedAt" to data.getLongExtra("capturedAt",0)))
            return
        }
        if(requestCode==ReceiptSaver.REQUEST){receiptSaver?.onResult(resultCode,data);return}
        super.onActivityResult(requestCode,resultCode,data)
    }
    override fun onDestroy(){scanReply?.error("SCAN_INTERRUPTED","Scan interrupted; please try again",null);scanReply=null;receiptSaver?.dispose();super.onDestroy()}
}
