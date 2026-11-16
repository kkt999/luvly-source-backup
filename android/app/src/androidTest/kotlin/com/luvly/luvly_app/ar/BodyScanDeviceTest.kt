package com.luvly.luvly_app.ar

import android.graphics.Bitmap
import android.graphics.Color
import android.test.InstrumentationTestCase
import com.google.mediapipe.framework.image.BitmapExtractor

/** Real Android/MediaPipe tests with synthetic pixels only; no camera, account,
 * profile write or user image. Camera/stance acceptance remains a user check. */
@Suppress("DEPRECATION")
class BodyScanDeviceTest: InstrumentationTestCase() {
    fun testInferenceReleasesOnlyItsOwnImageNotThePreview(){
        val preview=Bitmap.createBitmap(320,480,Bitmap.Config.ARGB_8888)
        preview.eraseColor(Color.GRAY)
        var inference: Bitmap?=null
        val result=withBodyScanImage(preview){input->inference=BitmapExtractor.extract(input);assertFalse(preview===inference);42}
        assertEquals(42,result);assertTrue(inference!!.isRecycled);assertFalse(preview.isRecycled)
        assertEquals(Color.GRAY,preview.getPixel(160,240));preview.recycle()
    }
    fun testFailedInferenceStillReleasesCopyAndKeepsPreviewUsable(){
        val preview=Bitmap.createBitmap(32,32,Bitmap.Config.ARGB_8888)
        var inference: Bitmap?=null
        try{withBodyScanImage(preview){input->inference=BitmapExtractor.extract(input);throw IllegalStateException("Synthetic inference error")};fail("Expected failure")}
        catch(_:IllegalStateException){}
        assertTrue(inference!!.isRecycled);assertFalse(preview.isRecycled);preview.getPixel(0,0);preview.recycle()
    }
    fun testInstalledPoseModelRunsOnDeviceWithoutInventingPersonOrRatios(){
        val preview=Bitmap.createBitmap(320,480,Bitmap.Config.ARGB_8888);preview.eraseColor(Color.GRAY)
        val tracker=LocalPoseTracker(instrumentation.targetContext)
        try{
            val result=withBodyScanImage(preview){tracker.detect(it,1000)}
            assertNotNull(result);assertTrue(result!!.landmarks().isEmpty())
            assertEquals("Step into view",BodyProportionScan().add(emptyList(),emptyList(),320,480,1000,128.0).guidance)
            assertFalse(preview.isRecycled);preview.getPixel(0,0)
        }finally{tracker.close();preview.recycle()}
    }
}
