package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test

class SceneLightTest {
    private fun gray(v: Int)=IntArray(100){0xff000000.toInt() or (v shl 16) or (v shl 8) or v}
    @Test fun brightnessBoundedAndMonotonic() {
        val low=SceneLight.estimate(gray(20))!!;val high=SceneLight.estimate(gray(240))!!
        assertEquals(.72f,low,0f);assertEquals(1.12f,high,0f)
        assertTrue(SceneLight.estimate(gray(120))!! in low..high)
    }
    @Test fun saturatedClippedAndInsufficientSamplesDoNotInventLighting() {
        for(p in listOf(gray(0),gray(255),IntArray(100){0xffff0000.toInt()},IntArray(12){0xff808080.toInt()}))
            assertNull(SceneLight.estimate(p))
    }
    @Test fun lightingSmoothsAndStaleFramesCannotChangeIt() {
        val light=SceneLight();val first=light.observe(gray(20),1000)
        assertTrue(first in .95f..1f)
        assertEquals(first,light.observe(gray(240),1000),0f)
        val next=light.observe(gray(20),1100)
        assertTrue(next<first && first-next<.03f)
        assertEquals(next,light.observe(gray(0),1200),0f)
        light.reset();assertEquals(first,light.observe(gray(20),2000),0f)
    }
}
