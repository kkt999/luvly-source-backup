package com.luvly.luvly_app.ar

import java.nio.FloatBuffer
import org.junit.Assert.*
import org.junit.Test

class BodyGirthScanTest {
    private fun pose(side: Boolean, armsForward: Boolean = true): List<BodyProportionScan.Joint> {
        val p = MutableList(33) { BodyProportionScan.Joint(.5, .5, 0.0, 1.0) }
        p[0] = p[0].copy(y = .16)
        p[11] = p[11].copy(x = if (side) .49 else .36, y = .27)
        p[12] = p[12].copy(x = if (side) .51 else .64, y = .27)
        p[13] = p[13].copy(x = .25, y = if (side && armsForward) .27 else .44)
        p[14] = p[14].copy(x = .75, y = if (side && armsForward) .27 else .44)
        p[23] = p[23].copy(x = if (side) .49 else .4, y = .56)
        p[24] = p[24].copy(x = if (side) .51 else .6, y = .56)
        p[27] = p[27].copy(y = .875)
        p[28] = p[28].copy(y = .875)
        return p
    }

    private fun world(side: Boolean): List<BodyProportionScan.Joint> {
        val p = MutableList(33) { BodyProportionScan.Joint(0.0, 0.0, 0.0, 1.0) }
        p[0] = p[0].copy(z = -.15)
        for ((left, right, span) in listOf(Triple(11, 12, .20), Triple(23, 24, .14))) {
            p[left] = if (side) p[left].copy(z = -span) else p[left].copy(x = -span)
            p[right] = if (side) p[right].copy(z = span) else p[right].copy(x = span)
        }
        return p
    }

    private fun silhouette(side: Boolean, clipped: Boolean = false): BodyGirthScan.Mask {
        val pixels = FloatArray(240 * 320)
        for (y in (if (clipped) 0 else 32)..289) {
            val width = when (y) {
                in 105..133 -> if (side) 48 else 64
                in 135..165 -> if (side) 40 else 52
                in 169..196 -> if (side) 54 else 72
                else -> 32
            }
            for (x in 120 - width / 2 until 120 + width / 2) pixels[y * 240 + x] = 1f
        }
        return BodyGirthScan.Mask(240, 320, FloatBuffer.wrap(pixels))
    }

    private fun feed(scan: BodyGirthScan, side: Boolean, time: Long,
                     mask: BodyGirthScan.Mask? = silhouette(side), armsForward: Boolean = true) =
        scan.add(listOf(pose(side, armsForward)), listOf(world(side)), mask, time, 100.0)

    private fun front(scan: BodyGirthScan) {
        for (i in 0..5) assertNull(feed(scan, false, 1000 + i * 200L).estimate)
        assertEquals(50, feed(scan, false, 2200).percent)
    }

    @Test fun requiresTwoStableViewsAndUsesTheEnteredHeightForTheScale() {
        val scan = BodyGirthScan(170.0)
        front(scan)
        assertEquals(50, feed(scan, false, 2400).percent)
        for (i in 0..5) assertNull(feed(scan, true, 2600 + i * 200L).estimate)
        val result = requireNotNull(feed(scan, true, 3800).estimate)
        val scale = 170.0 / 258
        assertEquals(BodyGirthScan.ellipsePerimeter(64 * scale, 48 * scale), result.bust, .001)
        assertEquals(BodyGirthScan.ellipsePerimeter(52 * scale, 40 * scale), result.waist, .001)
        assertEquals(BodyGirthScan.ellipsePerimeter(72 * scale, 54 * scale), result.hips, .001)
        val taller = BodyGirthScan(187.0)
        front(taller)
        for (i in 0..5) feed(taller, true, 2400 + i * 200L)
        assertEquals(result.bust * 1.1, requireNotNull(feed(taller, true, 3600).estimate).bust, .001)
    }

    @Test fun rejectsMissingClippedOrObscuredViewsAndExpiresUnfinishedScans() {
        val scan = BodyGirthScan(170.0)
        assertEquals(0, feed(scan, true, 1000).percent)
        assertEquals(0, feed(scan, false, 1200, null).percent)
        assertEquals(0, feed(scan, false, 1400, silhouette(false, clipped = true)).percent)
        scan.reset()
        front(scan)
        for (i in 0..8) {
            val attempt = feed(scan, true, 2400 + i * 200L, armsForward = false)
            assertEquals(50, attempt.percent)
            assertNull(attempt.estimate)
        }
        assertEquals(0, feed(scan, true, 95000).percent)
        assertEquals(0, feed(scan, true, 95200).percent)
    }
}
