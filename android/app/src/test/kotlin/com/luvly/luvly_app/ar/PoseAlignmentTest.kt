package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class PoseAlignmentTest {
    @Test fun visibleFeetAdjustOnlySkirtWithoutMovingBodiceAnchors() {
        val points=body().apply {
            this[0]=BodyPoint(.5f,.1f,1f)
            this[11]=BodyPoint(.3f,.25f,1f);this[12]=BodyPoint(.7f,.25f,1f)
            this[23]=BodyPoint(.4f,.5f,1f);this[24]=BodyPoint(.6f,.5f,1f)
            for(i in listOf(27,28,31,32))this[i]=BodyPoint(if(i%2==0).58f else .42f,.94f,1f)
        }
        val anchors=DressAnchors(1.40f,.97f,.31f)
        val full=PoseAlignment.align(points,600,900,600,900,anchors)!!
        assertTrue(full.hemAdjustment>0f)
        val adjustedSkirt=anchors.hipY*full.heightScale*(1-.35f*full.hemAdjustment)
        assertEquals((.94f-.5f)*900,adjustedSkirt,.01f)
        points[31]=points[31].copy(confidence=.1f)
        val cropped=PoseAlignment.align(points,600,900,600,900,anchors)!!
        assertEquals(0f,cropped.hemAdjustment,0f)
        assertEquals(full.copy(hemAdjustment=0f),cropped)
    }
    @Test fun manualTorsoOffsetsAreIndependentAndLeaveSkirtScaleUnchanged() {
        val p=DressPose(10f,20f,300f,400f,.1f,.3f,.2f)
        assertEquals(p.copy(chestFit=.7f),PoseAlignment.adjustTorso(p,.5f,0f))
        assertEquals(p.copy(waistFit=.8f),PoseAlignment.adjustTorso(p,0f,.5f))
        assertEquals(p.copy(chestFit=1f,waistFit=0f),PoseAlignment.adjustTorso(p,5f,-5f))
        assertEquals(p,PoseAlignment.adjustTorso(p,0f,0f))
    }
    @Test fun torsoFitIsIndependentBoundedAndSmoothed() {
        val anchors=DressAnchors(1.45f,.97f,.4f,true)
        val slim=body()
        val broad=body().apply {
            this[23]=BodyPoint(.32f,.65f,1f); this[24]=BodyPoint(.68f,.65f,1f)
        }
        val a=PoseAlignment.align(slim,400,800,800,800,anchors)!!
        val b=PoseAlignment.align(broad,400,800,800,800,anchors)!!
        assertTrue(b.waistFit>a.waistFit)
        assertTrue(b.chestFit>a.chestFit)
        assertEquals(a.widthScale,b.widthScale,.001f)
        assertEquals(a.heightScale,b.heightScale,.001f)
        assertTrue(b.waistFit in 0f..1f && b.chestFit in 0f..1f)
        val mixed=PoseAlignment.smooth(a,b)
        assertTrue(mixed.waistFit>a.waistFit && mixed.waistFit<b.waistFit)
        assertEquals(0f,PoseAlignment.align(broad,400,800,800,800)!!.waistFit,0f)
    }
    @Test fun framingRequiresConfidentVisibleFeet() {
        val p=body()
        assertTrue(PoseAlignment.fullBodyVisible(p))
        p[31]=BodyPoint(.4f,1.1f,1f)
        assertFalse(PoseAlignment.fullBodyVisible(p))
        p[31]=BodyPoint(.4f,.9f,.2f)
        assertFalse(PoseAlignment.fullBodyVisible(p))
        assertFalse(PoseAlignment.fullBodyVisible(emptyList()))
    }
    @Test fun princessUsesItsOwnAnchorsAndKeepsHipAligned() {
        val a=ArDressCatalogue.resolve("princess-wedding","assets/models/princess_wedding.glb")!!.anchors
        val p=PoseAlignment.align(body(),400,800,800,800,a)!!
        assertEquals(320f/.48f,p.heightScale,.01f)
        assertEquals(280f,p.y+(a.hipY-a.shoulderY)*p.heightScale,.01f)
        // Adapted neckline is just below shoulders; waist lies above hips.
        val neckline=p.y+(1.43f-a.shoulderY)*p.heightScale
        val waist=p.y+(1.10f-a.shoulderY)*p.heightScale
        assertTrue(neckline < p.y && neckline > p.y-20f)
        assertTrue(waist > 280f && waist < neckline)
        // 0.378-unit fitted bodice spans ~95% of the detected shoulder width.
        assertEquals(151.2f,.378f*p.widthScale,.1f)
        assertNull(PoseAlignment.align(body(),400,800,800,800,DressAnchors(1f,1f,.4f)))
    }
    @Test fun clippingExcludesBothLetterboxOrientations() {
        assertArrayEquals(intArrayOf(0,250,600,1050),PoseAlignment.imageBounds(600,800,600,1300))
        assertArrayEquals(intArrayOf(200,0,600,800),PoseAlignment.imageBounds(400,800,800,800))
        assertArrayEquals(intArrayOf(0,0,600,800),PoseAlignment.imageBounds(600,800,600,800))
        assertArrayEquals(intArrayOf(0,0,0,0),PoseAlignment.imageBounds(0,800,600,800))
    }
    private fun body(): MutableList<BodyPoint> {
        val p=MutableList(33) { BodyPoint(.5f,.5f,1f) }
        p[11]=BodyPoint(.3f,.25f,1f); p[12]=BodyPoint(.7f,.25f,1f)
        p[23]=BodyPoint(.4f,.65f,1f); p[24]=BodyPoint(.6f,.65f,1f)
        return p
    }
    @Test fun centeredBodyUsesLetterboxingAndMetreAnchors() {
        val p=PoseAlignment.align(body(),400,800,800,800)!!
        assertEquals(400f,p.x,.01f); assertEquals(600f,p.y,.01f)
        assertEquals(400f,p.widthScale,.01f)
        assertEquals(320f/.52f,p.heightScale,.01f)
        // Model hip anchor must land on the observed hip midpoint, not below it.
        assertEquals(280f,p.y+(PoseAlignment.MODEL_HIP_Y-PoseAlignment.MODEL_SHOULDER_Y)*p.heightScale,.01f)
        assertEquals(0f,p.roll,.01f)
    }
    @Test fun missingAndUnreliableBodiesAreHidden() {
        assertNull(PoseAlignment.align(emptyList(),400,800,400,800))
        val p=body(); p[11]=BodyPoint(.3f,.25f,.2f)
        assertNull(PoseAlignment.align(p,400,800,400,800))
        assertNull(PoseAlignment.align(body(),0,800,400,800))
        val nan=body();nan[11]=nan[11].copy(confidence=Float.NaN)
        assertNull(PoseAlignment.align(nan,400,800,400,800))
    }
    @Test fun smoothingResetsAndReducesJumps() {
        val a=DressPose(0f,0f,100f,100f,0f)
        val b=DressPose(100f,100f,200f,200f,.2f)
        assertEquals(b,PoseAlignment.smooth(null,b))
        assertEquals(35f,PoseAlignment.smooth(a,b).x,.01f)
    }
}
