package com.luvly.luvly_app.ar

import java.nio.FloatBuffer
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** Experimental two-view ellipse estimates. This is not a calibrated body scanner. */
internal class BodyGirthScan(private val heightCm: Double) {
    data class Estimate(val bust: Double, val waist: Double, val hips: Double)
    data class Update(val message: String, val percent: Int, val estimate: Estimate? = null)
    data class Mask(val width: Int, val height: Int, val values: FloatBuffer) {
        fun contains(x: Int, y: Int) = values.get(y * width + x) >= .65f
    }

    private data class Frame(val time: Long, val centerX: Double, val centerY: Double,
                             val height: Int, val widths: List<Double>)
    private val samples = ArrayList<Frame>()
    private var front: Frame? = null
    private val sections = listOf(.23, .29, .35, .41, .47, .55, .61, .67, .73, .79, .91, .97, 1.03, 1.09, 1.15)

    fun reset() {
        front = null
        samples.clear()
    }

    private fun retry(message: String): Update {
        samples.clear()
        return Update(message, if (front == null) 0 else 50)
    }

    fun add(people: List<List<BodyProportionScan.Joint>>, world: List<List<BodyProportionScan.Joint>>,
            mask: Mask?, time: Long, brightness: Double): Update {
        val previous = front
        if (previous != null && (time <= previous.time || time - previous.time > 90000)) {
            reset()
            return retry("Scan restarted. Face the camera again.")
        }
        val side = previous != null
        val instruction = if (side) "Turn sideways on the same spot" else "Face the camera"
        if (!brightness.isFinite() || brightness < 40) return retry("Find brighter, even lighting")
        if (people.size != 1 || world.size != 1 || mask == null) {
            return retry("Keep one person in view from head to toes")
        }
        val p = people.single()
        val w = world.single()
        if (p.size < 33 || w.size < 33 || mask.width < 32 || mask.height < 32 ||
            mask.values.limit() < mask.width * mask.height) return retry("Adjust your position and try again")
        val torsoJoints = listOf(11, 12, 23, 24)
        val required = torsoJoints + listOf(0, 27, 28)
        if (required.any { !p[it].x.isFinite() || !p[it].y.isFinite() ||
                p[it].x !in .03.. .97 || p[it].y !in .02.. .98 } ||
            p[0].confidence < .5 || maxOf(p[27].confidence,p[28].confidence) < .5 ||
            (if (side) listOf(11 to 12, 23 to 24).any { (a,b) -> maxOf(p[a].confidence,p[b].confidence) < .55 }
             else torsoJoints.any { p[it].confidence < .65 })) {
            return retry("Keep your whole body in the frame")
        }
        if (torsoJoints.any { !w[it].x.isFinite() || !w[it].y.isFinite() || !w[it].z.isFinite() } ||
            !w[0].z.isFinite()) return retry(instruction)
        val frontShoulder = hypot(w[11].x - w[12].x, w[11].y - w[12].y)
        val frontHip = hypot(w[23].x - w[24].x, w[23].y - w[24].y)
        val shoulderDepth = abs(w[11].z - w[12].z)
        val hipDepth = abs(w[23].z - w[24].z)
        if (side) {
            if (shoulderDepth < .12 || hipDepth < .08 ||
                shoulderDepth < frontShoulder * 1.4 || hipDepth < frontHip * 1.4) return retry(instruction)
        } else if (frontShoulder < .08 || frontHip < .05 || shoulderDepth > frontShoulder * .3 ||
            hipDepth > frontHip * .34 || w[0].z >= (w[11].z + w[12].z) / 2 - .02) {
            return retry(instruction)
        }
        val shoulderY = (p[11].y + p[12].y) / 2
        val hipY = (p[23].y + p[24].y) / 2
        val shoulderX = (p[11].x + p[12].x) / 2
        val hipX = (p[23].x + p[24].x) / 2
        val torso = hipY - shoulderY
        if (torso < .13 || abs(hipX - shoulderX) * mask.width > torso * mask.height * .22) {
            return retry("Stand straight and keep the phone upright")
        }
        if (side) {
            val nearArm = if (w[11].z < w[12].z) 13 else 14
            if (p[nearArm].confidence < .45 || !p[nearArm].y.isFinite() ||
                p[nearArm].y > shoulderY + torso * .17) {
                return retry("Side view: reach both arms straight forward at shoulder height")
            }
        } else {
            val span = abs(p[11].x - p[12].x)
            if (listOf(13, 14).any { p[it].confidence < .45 || !p[it].x.isFinite() ||
                    abs(p[it].x - shoulderX) < span * .6 }) {
                return retry("Front view: hold your arms slightly away from your body")
            }
        }

        val centerX = (shoulderX + hipX) / 2
        // Use the central corridor for height, so outstretched hands cannot set its endpoints.
        val corridor = ((centerX - .13) * mask.width).roundToInt().coerceAtLeast(1)..
            ((centerX + .13) * mask.width).roundToInt().coerceAtMost(mask.width - 2)
        fun bodyRow(y: Int) = corridor.any { mask.contains(it,y) && mask.contains(it + 1,y) }
        val top = (0 until mask.height).firstOrNull(::bodyRow)
        val bottom = (mask.height - 1 downTo 0).firstOrNull(::bodyRow)
        if (top == null || bottom == null || top < 2 || bottom > mask.height - 3 ||
            top > p[0].y * mask.height || bottom < maxOf(p[27].y,p[28].y) * mask.height ||
            bottom - top < mask.height * .53) return retry("Fit your head and feet in the outline")
        val pixelsTall = bottom - top + 1
        if (previous != null && abs(pixelsTall - previous.height) > previous.height * .09) {
            return retry("Return to the same spot and leave the phone fixed")
        }

        val widths = ArrayList<Double>(sections.size)
        for (section in sections) {
            val x = ((shoulderX + (hipX - shoulderX) * section) * mask.width).roundToInt()
            val y = ((shoulderY + torso * section) * mask.height).roundToInt()
            if (x !in 2 until mask.width - 2 || y !in 2 until mask.height - 2) {
                return retry("Keep your torso inside the outline")
            }
            val rows = (-2..2).map { offset -> widthAt(mask, x, y + offset) }.filterNotNull()
            if (rows.size < 3) return retry("Keep your outline clear and wear close-fitting clothes")
            val width = median(rows) * heightCm / pixelsTall
            if (width !in 8.0..85.0) return retry("Keep your arms clear of your torso")
            widths.add(width)
        }
        val frame = Frame(time,centerX,(shoulderY + hipY) / 2,pixelsTall,widths)
        val start = samples.firstOrNull()
        val last = samples.lastOrNull()
        if (start != null && last != null &&
            (time <= last.time || time - last.time > 1200 ||
             abs(frame.height - start.height) > start.height * .045 ||
             hypot(frame.centerX - start.centerX,frame.centerY - start.centerY) > .035)) samples.clear()
        samples.add(frame)
        val spanMs = time - samples.first().time
        val progress = (minOf(samples.size / 7.0,spanMs / 1000.0) * 49).toInt().coerceIn(0,49)
        if (samples.size < 7 || spanMs < 1000) {
            return Update(if (side) "Hold still for the side view" else "Hold still for the front view",
                (if (side) 50 else 0) + progress)
        }
        val stableWidths = sections.indices.map { i ->
            val series = samples.map { it.widths[i] }.sorted()
            val middle = median(series)
            if ((series[series.size * 4 / 5] - series[series.size / 5]) > middle * .12) {
                return retry("Hold still and keep your clothing outline clear")
            }
            middle
        }
        if (previous == null) {
            front = frame.copy(height = median(samples.map { it.height.toDouble() }).roundToInt(), widths = stableWidths)
            samples.clear()
            return Update("Front captured. Turn sideways in the same spot and reach forward.",50)
        }
        val perimeters = previous.widths.zip(stableWidths, ::ellipsePerimeter)
        val result = Estimate(perimeters.subList(0,5).max(),perimeters.subList(5,10).min(),perimeters.subList(10,15).max())
        if (listOf(result.bust,result.waist,result.hips).any { it !in 30.0..300.0 }) {
            reset()
            return retry("The outline was unclear. Scan both views again.")
        }
        return Update("Both views captured",100,result)
    }

    private fun widthAt(mask: Mask, x: Int, y: Int): Double? {
        if (!mask.contains(x,y)) return null
        var left = x
        var right = x
        while (left > 0 && mask.contains(left - 1,y)) left--
        while (right < mask.width - 1 && mask.contains(right + 1,y)) right++
        return if (left < 2 || right > mask.width - 3) null else (right - left + 1).toDouble()
    }

    private fun median(numbers: List<Double>): Double {
        val sorted = numbers.sorted()
        return (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2
    }

    companion object {
        fun ellipsePerimeter(width: Double, depth: Double): Double {
            val a = width / 2
            val b = depth / 2
            val h = (a - b) * (a - b) / ((a + b) * (a + b))
            return Math.PI * (a + b) * (1 + 3 * h / (10 + sqrt(4 - 3 * h)))
        }
    }
}
