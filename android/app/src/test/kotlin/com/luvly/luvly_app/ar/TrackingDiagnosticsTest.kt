package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class TrackingDiagnosticsTest {
    @Test fun compactHudAndDetailedSnapshotKeepPerformanceAndFitSeparate() {
        val d=TrackingDiagnostics()
        for(t in listOf(1000L,1200L,1400L))d.observe(t,t-180,true,2f,"none",
            "image-anchored-profile",FrameTimings(10,150,20,"GPU live"),50f)
        assertTrue(d.compact(1400).contains("5.0 updates/s"))
        assertTrue(d.compact(1400).contains("Profile image fit"))
        assertEquals(2,d.compact(1400).lines().size)
        assertTrue(d.description(1400).contains("pose 150 ms"))
        assertTrue(d.description(1400).contains("not used for rendering): 50 px"))
        assertTrue(d.compact(2200).contains("Tracking paused"))
        assertFalse(d.compact(2200).contains("tracked"))
        assertTrue(d.compact(4000).contains("Waiting for frames"))
    }
    @Test fun recordsBoundedReasonSummaryWithoutCoordinatesAndRetainsSessionCounts() {
        val d=TrackingDiagnostics()
        d.observe(1000,950,false,null,"world_confidence")
        d.observe(1100,1050,false,null,"turn_limit")
        d.observe(1200,1150,true,2f,"none")
        val text=d.description(1200)
        assertTrue(text.contains("Latest: tracked"))
        assertTrue(text.contains("world_confidence: 1"));assertTrue(text.contains("turn_limit: 1"))
        assertTrue(d.description(5000).contains("turn_limit: 1"))
        d.reset();assertFalse(d.description(5000).contains("turn_limit"))
    }
}
