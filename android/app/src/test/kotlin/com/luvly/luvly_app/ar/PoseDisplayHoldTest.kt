package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class PoseDisplayHoldTest {
    @Test fun holdsOnlyBriefMisses() {
        val hold=PoseDisplayHold()
        assertFalse(hold.observe(false,100))
        assertTrue(hold.observe(true,200))
        assertTrue(hold.observe(false,400))
        assertFalse(hold.observe(false,501))
        assertTrue(hold.observe(true,600))
        assertFalse(hold.observe(false,599))
    }
}
