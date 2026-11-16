package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class CroppedArmOcclusionTest {
    private fun body()=MutableList(33) { BodyPoint(.5f,.5f,0f) }.apply {
        this[0]=BodyPoint(.5f,.23f,1f);this[2]=BodyPoint(.46f,.2f,1f);this[5]=BodyPoint(.54f,.2f,1f)
        this[11]=BodyPoint(.22f,.48f,1f,0f);this[12]=BodyPoint(.78f,.48f,1f,0f)
        this[23]=BodyPoint(.35f,1.1f,.1f);this[24]=BodyPoint(.65f,1.1f,.1f)
        this[13]=BodyPoint(.30f,.72f,1f,-.15f);this[15]=BodyPoint(.55f,.60f,1f,-.20f)
    }
    private fun masks(p: List<BodyPoint>)=ArmOcclusion.capsules(p,600,900,skinIntersection=true)

    @Test fun crossedArmHasMaskWithoutHipDepthButNeverBareGeometry() {
        assertEquals(2,masks(body()).size)
        assertTrue(ArmOcclusion.capsules(body(),600,900).isEmpty())
    }
    @Test fun hiddenHipsInFullFrameDoNotEnableCroppedMask() {
        val p=body().apply {
            this[23]=this[23].copy(y=.8f);this[24]=this[24].copy(y=.8f)
            this[11]=this[11].copy(x=.33f);this[12]=this[12].copy(x=.67f)
        }
        assertTrue(masks(p).isEmpty())
    }
    @Test fun unknownDepthAndBehindArmsNeverCutGown() {
        for(z in listOf(Float.NaN,.2f)) {
            val p=body().apply { this[13]=this[13].copy(z=z);this[15]=this[15].copy(z=z) }
            assertTrue(masks(p).isEmpty())
        }
        assertTrue(masks(body().apply {this[11]=this[11].copy(z=Float.NaN)}).isEmpty())
    }
    @Test fun frontHandWithBehindElbowOnlyRevealsForegroundSegment() {
        val p=body().apply {this[13]=this[13].copy(z=.1f)}
        val c=masks(p).single()
        assertTrue(c.ax>p[13].x*600+20)
        assertEquals(p[15].x*600,c.bx,.01f)
    }
    @Test fun turnUsesLocalShoulderDepthAndRejectsDeepProfile() {
        val p=body().apply {
            this[11]=this[11].copy(z=-.2f);this[12]=this[12].copy(z=.2f)
            this[13]=this[13].copy(x=.25f,z=-.12f)
            this[15]=this[15].copy(x=.45f,z=-.12f)
        }
        // Elbow is behind the near shoulder plane; only the crossing hand qualifies.
        val c=masks(p).single()
        assertTrue(c.ax>p[13].x*600)
        p[12]=p[12].copy(z=.4f)
        assertTrue(masks(p).isEmpty())
    }
    @Test fun mirroredAndScaledCropHasSameMask() {
        val a=masks(body());val b=masks(body().map {it.copy(x=1-it.x)})
        val c=ArmOcclusion.capsules(body(),1200,1800,skinIntersection=true)
        assertEquals(a.size,b.size);assertEquals(a.size,c.size)
        for(i in a.indices) {
            assertEquals(600-a[i].ax,b[i].ax,.01f)
            assertEquals(a[i].startRadius*2,c[i].startRadius,.01f)
        }
    }
    @Test fun missingFaceAndArmsAboveNeckDoNotCutGown() {
        assertTrue(masks(body().apply {this[0]=this[0].copy(confidence=0f)}).isEmpty())
        assertTrue(masks(body().apply {
            this[13]=this[13].copy(y=.2f);this[15]=this[15].copy(y=.25f)
        }).isEmpty())
    }
    @Test fun croppedMaskStillRequiresCurrentImageEvidence() {
        assertNull(ArmSkinMask.pixels(SkinConfidence(0,0,floatArrayOf()),body(),600,900))
        val empty=SkinConfidence(60,90,FloatArray(60*90))
        val pixels=ArmSkinMask.pixels(empty,body(),600,900)!!
        assertTrue(pixels.all {it ushr 24==0})
    }
}
