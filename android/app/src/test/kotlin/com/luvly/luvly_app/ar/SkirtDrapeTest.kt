package com.luvly.luvly_app.ar

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class SkirtDrapeTest {
    private fun matrix(yaw: Float,roll: Float,width: Float=300f,adjust: Float=1f):FloatArray {
        val a=Math.toRadians(yaw.toDouble()).toFloat()
        val spatial=SpatialDressPose(Vec3(0f,0f,-2f),Vec3(cos(a),0f,-sin(a)),Vec3(0f,1f,0f),1f,1f,
            PerspectiveProjection(600,900,800f,800f,300f,450f,"fixture"),0f)
        return GarmentRenderTransform.matrix(DressPose(300f,600f,width,320f,roll,
            spatial=spatial,unprojectedWidth=true),DressAnchors(),adjust)
    }
    @Test fun uprightAndTurnedUprightAreUnchanged() {
        for(yaw in listOf(-90f,-35f,0f,35f,90f,92f))
            assertArrayEquals(floatArrayOf(0f,0f),SkirtDrape.weights(matrix(yaw,0f)),1e-6f)
    }
    @Test fun leanCorrectionHasSameScreenDirectionAtEveryYawAndManualWidth() {
        for(yaw in listOf(-92f,-90f,-45f,0f,45f,90f,92f))for(roll in listOf(-.25f,.25f))for(adjust in listOf(.8f,1.2f)) {
            val m=matrix(yaw,roll,adjust=adjust);val w=SkirtDrape.weights(m)
            val dx=SkirtDrape.TARGET_SCALE*w[0];val dz=SkirtDrape.TARGET_SCALE*w[1]
            val renderedX=m[0]*dx+m[8]*dz
            val renderedZ=m[2]*dx+m[10]*dz
            // Cancel 70% of horizontal displacement per metre below the blend.
            assertEquals(m[4]*.70f,renderedX,.002f)
            assertEquals(0f,renderedZ,.002f)
            assertTrue(renderedX*(-m[4])<0f)
        }
    }
    @Test fun correctionIsBoundedForLargeBendsAndExtremeScaleRatios() {
        for(width in listOf(.01f,30f,300f,900f))for(roll in listOf(-1.2f,-.3f,0f,.3f,1.2f)) {
            val w=SkirtDrape.weights(matrix(65f,roll,width))
            assertTrue(w.all {it.isFinite() && abs(it)<=1f})
        }
    }
    @Test fun invalidTransformDoesNotDeformGarment() {
        for(m in listOf(FloatArray(16),FloatArray(8),FloatArray(16){Float.NaN}))
            assertArrayEquals(floatArrayOf(0f,0f),SkirtDrape.weights(m),0f)
    }
    @Test fun smallLeanCrossesZeroContinuouslyAndMirrors() {
        val left=SkirtDrape.weights(matrix(40f,-.001f));val right=SkirtDrape.weights(matrix(40f,.001f))
        for(i in 0..1) { assertEquals(-left[i],right[i],1e-7f);assertTrue(abs(left[i])<.002f) }
    }
}
