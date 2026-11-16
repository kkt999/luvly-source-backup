package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class PreviewEligibilityTest {
    @Test fun timerCanStartWithoutAnyDetectedPose() {
        val readiness=PreviewReadiness()
        assertFalse(readiness.ready(1000))
        assertTrue(PreviewEligibility.canPress(true,true,true,false,false,false))
    }
    @Test fun countdownCanBeCancelledEvenIfCameraOrTrackingStalls() {
        assertTrue(PreviewEligibility.canPress(true,true,false,false,true,false))
    }
    @Test fun retakeRemainsAvailableForFrozenPreview() {
        assertTrue(PreviewEligibility.canPress(true,true,false,true,false,false))
    }
    @Test fun noTimerWhenCameraOrModelUnavailableOrAppInactive() {
        assertFalse(PreviewEligibility.canPress(true,false,true,false,false,false))
        assertFalse(PreviewEligibility.canPress(true,true,false,false,false,false))
        assertFalse(PreviewEligibility.canPress(false,true,true,false,false,false))
        assertFalse(PreviewEligibility.canPress(true,true,true,true,false,true))
    }
}
