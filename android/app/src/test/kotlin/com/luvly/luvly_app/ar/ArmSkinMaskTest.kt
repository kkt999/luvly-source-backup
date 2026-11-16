package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class ArmSkinMaskTest {
    private fun body(): List<BodyPoint> = MutableList(33){BodyPoint(.5f,.5f,0f)}.apply {
        this[11]=BodyPoint(.3f,.25f,1f,0f);this[12]=BodyPoint(.7f,.25f,1f,0f)
        this[23]=BodyPoint(.4f,.6f,1f,0f);this[24]=BodyPoint(.6f,.6f,1f,0f)
        this[13]=BodyPoint(.32f,.5f,1f,-.15f);this[15]=BodyPoint(.52f,.48f,1f,-.2f)
    }
    @Test fun noSkinOrUncertainSkinDoesNotRevealUnderlyingClothes() {
        for(v in listOf(0f,.5f,Float.NaN)) {
            val mask=ArmSkinMask.pixels(SkinConfidence(100,100,FloatArray(10000){v}),body(),600,900)!!
            assertTrue(mask.all { it ushr 24 == 0 })
        }
    }
    @Test fun intersectionShowsOnlySkinNearForegroundForearm() {
        val mask=ArmSkinMask.pixels(SkinConfidence(100,100,FloatArray(10000){1f}),body(),600,900)!!
        assertEquals(255,mask[49*100+40] ushr 24)
        assertEquals(0,mask[10*100+50] ushr 24) // No head/neck cutout.
        assertEquals(0,mask[75*100+50] ushr 24) // No arbitrary torso cutout.
        assertEquals(0,mask[49*100+90] ushr 24) // No background cutout.
    }
    @Test fun missingGeometryOrMalformedMasksAreIgnored() {
        assertNull(ArmSkinMask.pixels(SkinConfidence(10,10,FloatArray(3)),body(),600,900))
        assertNull(ArmSkinMask.pixels(SkinConfidence(10,10,FloatArray(100)),emptyList(),600,900))
    }
    @Test fun skinConfidenceFeathersEdgesInsteadOfHardRectangle() {
        val mask=ArmSkinMask.pixels(SkinConfidence(100,100,FloatArray(10000){.725f}),body(),600,900)!!
        assertTrue((mask[49*100+40] ushr 24) in 125..130)
    }
    @Test fun upperArmSkinMayCoverDressButNeckAndUnknownSkinCannot() {
        val mask=ArmSkinMask.pixels(SkinConfidence(100,100,FloatArray(10000){1f}),body(),600,900)!!
        assertEquals(255,mask[40*100+31] ushr 24)
        assertEquals(0,mask[25*100+50] ushr 24)
        val noSkin=ArmSkinMask.pixels(SkinConfidence(100,100,FloatArray(10000)),body(),600,900)!!
        assertEquals(0,noSkin[40*100+31] ushr 24)
    }
    @Test fun profileSearchDoesNotCollapseWithProjectedShoulderWidth() {
        val p=body().toMutableList()
        p[11]=p[11].copy(x=.49f,z=-.1f);p[12]=p[12].copy(x=.51f,z=.1f)
        p[13]=p[13].copy(x=.50f,y=.45f,z=-.2f)
        p[15]=p[15].copy(x=.60f,y=.5f,z=-.3f)
        assertTrue(ArmOcclusion.capsules(p,600,900).isEmpty())
        assertTrue(ArmOcclusion.capsules(p,600,900,skinIntersection=true).isNotEmpty())
        val mask=ArmSkinMask.pixels(SkinConfidence(100,100,FloatArray(10000){1f}),p,600,900)!!
        assertTrue(mask.any { it ushr 24>0 })
        assertEquals(0,mask[20*100+50] ushr 24)
    }
}
