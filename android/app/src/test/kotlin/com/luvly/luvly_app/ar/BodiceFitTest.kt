package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*

class BodiceFitTest {
    private val a=DressAnchors(1.45f,.97f,.4f,true,.53f)
    private fun pose(yaw: Float=0f)=DressPose(300f,500f,300f,320f,0f,.4f,.3f,
        spatial=SpatialDressPose(Vec3(0f,.52f,-2.5f),Vec3(cos(yaw*.0174533f),0f,-sin(yaw*.0174533f)),
            Vec3(0f,1f,0f),1f,1f,PerspectiveProjection(600,900,800f,800f,300f,450f,"test"),0f),
        unprojectedWidth=true)
    private fun points(dy: Float=0f)=MutableList(33){BodyPoint(.5f,.5f,1f)}.apply {
        this[11]=BodyPoint(.3f,.3f+dy,1f);this[12]=BodyPoint(.7f,.3f-dy,1f)
        this[23]=BodyPoint(.4f,.6f,1f);this[24]=BodyPoint(.6f,.6f,1f)
    }
    @Test fun sideNoiseCannotChangeCalibratedChestAndWaist() {
        val fit=BodiceFit();val original=fit.apply(pose(),points(),600,900,a)
        for(i in 0..20) {
            val p=fit.apply(pose(75f).copy(waistFit=1f,chestFit=.65f),points(),600,900,a)
            assertEquals(original.waistFit,p.waistFit,0f);assertEquals(original.chestFit,p.chestFit,0f)
        }
    }
    @Test fun frontRefinementIsSlowAndResetAllowsAnotherWearer() {
        val fit=BodiceFit();fit.apply(pose(),points(),600,900,a)
        val changed=fit.apply(pose().copy(waistFit=1f),points(),600,900,a)
        assertEquals(.424f,changed.waistFit,.0001f)
        fit.reset();assertEquals(1f,fit.apply(pose().copy(waistFit=1f),points(),600,900,a).waistFit,0f)
    }
    @Test fun shoulderArticulationChangesSignWithMirrorAndPreservesRoot() {
        val p=pose().let { it.copy(spatial=it.spatial!!.copy(right=Vec3(1f,.12f,0f))) }
        val left=BodiceFit.shoulderTilt(p,points(.02f),600,900,a)!!
        val mirrored=p.copy(spatial=p.spatial!!.copy(right=Vec3(1f,-.12f,0f)))
        val right=BodiceFit.shoulderTilt(mirrored,points(.02f).map { it.copy(x=1-it.x) },600,900,a)!!
        assertTrue(left>0);assertEquals(-left,right,.0001f)
        val shaped=BodiceFit().apply(p,points(.02f),600,900,a)
        assertTrue(shaped.shoulderTilt>0);assertEquals(p.x,shaped.x,0f);assertEquals(p.y,shaped.y,0f)
        assertEquals(p.hemAdjustment,shaped.hemAdjustment,0f)
        assertArrayEquals(GarmentRenderTransform.matrix(p,a),GarmentRenderTransform.matrix(shaped,a),0f)
    }
    @Test fun profileLowConfidenceAndInvalidInputsCannotAmplifyTilt() {
        assertNull(BodiceFit.shoulderTilt(pose(80f),points(.1f),600,900,a))
        assertNull(BodiceFit.shoulderTilt(pose(),points().apply { this[11]=this[11].copy(confidence=.4f) },600,900,a))
        assertNull(BodiceFit.shoulderTilt(pose(),points(),0,900,a))
        val extreme=pose().let { it.copy(spatial=it.spatial!!.copy(right=Vec3(1f,.5f,0f))) }
        assertEquals(1f,BodiceFit.shoulderTilt(extreme,points(.1f),600,900,a)!!,0f)
    }
    @Test fun imagePerspectiveSlopeCannotCreateFalseShoulderArticulation() {
        for(yaw in listOf(-40f,-25f,0f,25f,40f)) {
            assertEquals(0f,BodiceFit.shoulderTilt(pose(yaw),points(.04f),600,900,a)!!,.00001f)
        }
    }
    @Test fun unsupportedGarmentUnchangedAndTiltPassesThroughFilter() {
        val p=pose();assertEquals(p,BodiceFit().apply(p,points(.1f),600,900,DressAnchors()))
        val f=DressPoseFilter();f.observe(p,1000,.4f)
        val shown=f.observe(p.copy(shoulderTilt=.8f),1100,.4f).pose!!
        assertTrue(shown.shoulderTilt>0 && shown.shoulderTilt<.8f)
        assertFalse(f.observe(p.copy(shoulderTilt=Float.NaN),1200,.4f).accepted)
    }
}
