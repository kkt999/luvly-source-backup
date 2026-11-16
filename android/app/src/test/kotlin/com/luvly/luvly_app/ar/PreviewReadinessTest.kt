package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test
class PreviewReadinessTest {
    @Test fun requiresContinuousRecentDetection() {
        val r=PreviewReadiness();assertFalse(r.ready(1000))
        r.observe(true,1000);assertFalse(r.ready(1000))
        r.observe(true,1300);r.observe(true,1600);assertTrue(r.ready(1600))
        assertFalse(r.ready(2400));r.observe(true,2400);assertFalse(r.ready(2400))
        r.observe(false,2450);assertFalse(r.ready(2500))
    }
    @Test fun resetInvalidatesCapture() {
        val r=PreviewReadiness();r.observe(true,0);r.observe(true,600)
        assertTrue(r.ready(600));r.reset();assertFalse(r.ready(601))
    }
    @Test fun processingDelayOrWaitingOnOneFrameCannotInventContinuousDetection() {
        val r=PreviewReadiness()
        r.observe(true,1000)
        assertFalse(r.ready(1600)) // One old observation is not a 600 ms detection window.
        assertFalse(r.ready(1700))
        r.observe(true,1500)
        assertFalse(r.ready(1900)) // Only 500 ms of evidence, plus processing delay.
        r.observe(true,1600)
        assertTrue(r.ready(1950))
    }
}
