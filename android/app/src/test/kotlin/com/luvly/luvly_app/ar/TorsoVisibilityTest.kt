package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class TorsoVisibilityTest {
    @Test fun scoresMustBeFiniteAndSupportedByAStrongPair() {
        assertTrue(TorsoVisibility.reliable(listOf(.9f,.9f,.5f,.7f),true))
        assertTrue(TorsoVisibility.reliable(listOf(.5f,.7f,.9f,.9f),true))
        assertFalse(TorsoVisibility.reliable(listOf(.9f,.9f,.5f,.7f),false))
        assertFalse(TorsoVisibility.reliable(listOf(.6f,.6f,.6f,.6f),true))
        assertFalse(TorsoVisibility.reliable(listOf(.9f,.9f,.4f,.9f),true))
        assertFalse(TorsoVisibility.reliable(listOf(.9f,.9f,.5f,.5f),true))
        assertFalse(TorsoVisibility.reliable(listOf(Float.NaN,.9f,.9f,.9f),true))
        assertFalse(TorsoVisibility.reliable(listOf(2f,.9f,.9f,.9f),true))
    }
}
