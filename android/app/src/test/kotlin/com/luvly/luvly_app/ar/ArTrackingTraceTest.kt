package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class ArTrackingTraceTest {
    @Test fun boundedByCountAndTimeAndContainsNoAbsoluteClock() {
        val t=ArTrackingTrace(3)
        for(n in 0..4)t.record(1000000L+n*200,"frame",mapOf("yaw_deg" to n.toFloat()))
        assertEquals(3,t.size)
        val csv=t.csv(2090)
        assertTrue(csv.contains("400,\"frame\""));assertFalse(csv.contains("1000000"))
        t.record(1200000,"frame")
        assertEquals(1,t.size)
    }
    @Test fun exportSnapshotSurvivesClearAndResetEventsPreserveHistory() {
        val t=ArTrackingTrace();t.record(1000,"frame",mapOf("filter" to "pending_confirmation"))
        t.record(1100,"tracking_reset")
        val csv=t.csv(2090)
        t.clear();assertEquals(0,t.size)
        assertTrue(csv.contains("pending_confirmation"));assertTrue(csv.contains("tracking_reset"))
        assertFalse(t.csv(2090).contains("pending_confirmation"))
    }
    @Test fun invalidNumbersAreBlankAndStringsCannotInjectSpreadsheetFormulas() {
        val t=ArTrackingTrace()
        t.record(1000,"frame",mapOf("yaw_deg" to Float.NaN,"depth_ratio" to Float.POSITIVE_INFINITY,
            "model" to "=bad,\"value\"\nnext","yaw_delta" to -40f))
        val csv=t.csv(2090)
        assertFalse(csv.contains("NaN"));assertFalse(csv.contains("Infinity"))
        assertTrue(csv.contains("\"'=bad,\"\"value\"\" next\""))
        assertTrue(csv.contains("-40.0000"))
        assertEquals(4,csv.trimEnd().lines().size)
    }
    @Test fun rawCoordinatesAndObjectsAreRejectedBySchema() {
        val t=ArTrackingTrace()
        assertThrows(IllegalArgumentException::class.java) { t.record(1000,"frame",mapOf("joint_x" to .5f)) }
        assertThrows(IllegalArgumentException::class.java) { t.record(1000,"frame",mapOf("model" to Any())) }
        assertEquals(0,t.size)
    }
    @Test fun backwardsClockStartsNewRelativeTimeline() {
        val t=ArTrackingTrace();t.record(1000,"old");t.record(900,"new")
        assertEquals(1,t.size);assertTrue(t.csv(2090).contains("0,\"new\""))
        assertFalse(t.csv(2090).contains("\"old\""))
    }
    @Test fun inspectingFilterDeltasDoesNotChangeDecisions() {
        val baseline=DressPoseFilter();val inspected=DressPoseFilter()
        val p=DressPose(300f,400f,500f,500f,0f)
        for((index,next) in listOf(p,p.copy(x=800f),p.copy(x=800f),p.copy(x=800f),null).withIndex()) {
            val now=1000L+index*250
            inspected.diagnosticDelta(next,now,.4f)
            assertEquals(baseline.observe(next,now,.4f),inspected.observe(next,now,.4f))
        }
        assertEquals("missing_observation",inspected.decisionReason)
    }
}
