package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test
import kotlin.math.sqrt

class GownOrbitTest {
    @Test fun modelSpecificFramingIsRestoredByReset() {
        val o=GownOrbit(1.85);o.drag(80.0,10.0);o.scale(.5);o.reset()
        assertEquals(1.85,o.zoom,0.0);assertEquals(0.0,o.yaw,0.0);assertEquals(0.0,o.pitch,0.0)
    }
    private val center=floatArrayOf(0f,.7f,0f)
    @Test fun frontAndBackAreOppositeAndFinite() {
        val o=GownOrbit();val front=o.eye(center,1.5,.5)
        o.back();val back=o.eye(center,1.5,.5)
        assertTrue(front[2]>0);assertEquals(-front[2],back[2],.00001)
        assertTrue(back.all { it.isFinite() });assertEquals(.7,back[1],.00001)
    }
    @Test fun fullRotationReturnsToSamePosition() {
        val o=GownOrbit();val before=o.eye(center,1.5,.5)
        o.drag(360.0,0.0);assertArrayEquals(before,o.eye(center,1.5,.5),.00001)
    }
    @Test fun zoomAndTiltAreBoundedAndInvalidInputIgnored() {
        val o=GownOrbit();o.scale(Double.NaN);o.drag(Double.POSITIVE_INFINITY,0.0)
        assertEquals(1.45,o.zoom,0.0);assertEquals(0.0,o.yaw,0.0)
        o.scale(100.0);o.drag(900.0,1000.0)
        assertEquals(2.5,o.zoom,0.0);assertEquals(40.0,o.pitch,0.0)
        o.scale(.00001);o.drag(0.0,-1000.0)
        assertEquals(.75,o.zoom,0.0);assertEquals(-30.0,o.pitch,0.0)
        o.reset();assertEquals(0.0,o.yaw,0.0);assertEquals(1.45,o.zoom,0.0)
    }
    @Test fun narrowViewportMovesCameraBackToFitGown() {
        val o=GownOrbit()
        assertTrue(o.eye(center,1.5,.4)[2]>o.eye(center,1.5,1.5)[2])
    }
    @Test fun cameraNeverEntersBoundingSphereEvenAtMaximumZoom() {
        val o=GownOrbit();o.scale(2.5);o.drag(73.0,24.0)
        val eye=o.eye(center,1.5,2.0)
        val distance=sqrt(eye.indices.sumOf { (eye[it]-center[it])*(eye[it]-center[it]) })
        assertTrue(distance>1.5)
    }
}
