package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class ArmOcclusionTest {
    @Test fun wristInFrontWithElbowBehindClipsOnlySegmentedForegroundPortion() {
        val p=body();p[13]=p[13].copy(z=.06f)
        assertTrue(ArmOcclusion.capsules(p,600,900).isEmpty())
        val c=ArmOcclusion.capsules(p,600,900,skinIntersection=true).single()
        assertTrue(c.ax>p[13].x*600+20f)
        assertEquals(p[15].x*600,c.bx,.01f)
    }
    @Test fun forearmFrontToBackDoesNotRevealBehindWrist() {
        val p=body();p[15]=p[15].copy(z=.1f)
        val c=ArmOcclusion.capsules(p,600,900,skinIntersection=true).last()
        assertEquals(p[13].x*600,c.ax,.01f)
        assertTrue(c.bx<p[15].x*600-20f)
    }
    private fun body(): MutableList<BodyPoint> {
        val p=MutableList(33){BodyPoint(.5f,.5f,0f)}
        p[11]=BodyPoint(.3f,.25f,1f,0f);p[12]=BodyPoint(.7f,.25f,1f,0f)
        p[23]=BodyPoint(.4f,.6f,1f,0f);p[24]=BodyPoint(.6f,.6f,1f,0f)
        p[13]=BodyPoint(.32f,.5f,1f,-.15f);p[15]=BodyPoint(.52f,.48f,1f,-.2f)
        return p
    }
    @Test fun clearForearmInFrontOfBodyProducesNarrowCameraMask() {
        val mask=ArmOcclusion.capsules(body(),600,900).single()
        assertEquals(192f,mask.ax,.01f)
        assertEquals(450f,mask.ay,.01f)
        assertEquals(312f,mask.bx,.01f)
        assertTrue(mask.startRadius in 8f..12f)
        assertTrue(mask.endRadius<mask.startRadius)
    }
    @Test fun absentUnknownDepthLowConfidenceAndBehindArmsDoNotCutDress() {
        assertTrue(ArmOcclusion.capsules(emptyList(),600,900).isEmpty())
        for(p in listOf(BodyPoint(.32f,.5f,1f),BodyPoint(.32f,.5f,.7f,-.15f),
            BodyPoint(.32f,.5f,1f,.15f),BodyPoint(.32f,.5f,Float.NaN,-.15f))) {
            val points=body();points[13]=p
            assertTrue(ArmOcclusion.capsules(points,600,900).isEmpty())
        }
    }
    @Test fun lowConfidenceTorsoAndImplausibleArmAreRejected() {
        val points=body();points[11]=points[11].copy(confidence=.2f)
        assertTrue(ArmOcclusion.capsules(points,600,900).isEmpty())
        val longArm=body();longArm[15]=BodyPoint(.96f,.92f,1f,-.2f)
        assertTrue(ArmOcclusion.capsules(longArm,600,900).isEmpty())
    }
    @Test fun reliablePalmCanAlsoAppearInFront() {
        val points=body()
        points[17]=BodyPoint(.57f,.46f,1f,-.2f)
        points[19]=BodyPoint(.57f,.50f,1f,-.2f)
        assertEquals(2,ArmOcclusion.capsules(points,600,900).size)
    }
    @Test fun mirrorAndImageScalePreserveMaskGeometry() {
        val p=body()
        val normal=ArmOcclusion.capsules(p,600,900).single()
        val mirrored=ArmOcclusion.capsules(p.map { it.copy(x=1-it.x) },600,900).single()
        assertEquals(600-normal.ax,mirrored.ax,.01f)
        val doubled=ArmOcclusion.capsules(p,1200,1800).single()
        assertEquals(normal.startRadius*2,doubled.startRadius,.01f)
        assertEquals(normal.bx*2,doubled.bx,.01f)
    }
}
