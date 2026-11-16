package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test
class PreviewRecoveryTest {
    @Test fun onlyAcceptsFreshReadyPoseWithinRecoveryWindow() {
        val r=PreviewRecovery(1000)
        assertFalse(r.canCapture(999,true))
        assertFalse(r.canCapture(1100,false))
        assertTrue(r.canCapture(1600,true))
        assertTrue(r.canCapture(3999,true))
        assertFalse(r.canCapture(4000,true))
        assertFalse(r.canCapture(9000,true))
    }
}
