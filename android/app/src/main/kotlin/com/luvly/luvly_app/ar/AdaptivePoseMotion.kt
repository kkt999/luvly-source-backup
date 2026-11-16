package com.luvly.luvly_app.ar

import kotlin.math.*

/** Speed-adaptive low-pass coefficients inspired by the 1 Euro filter.
 * Signed raw-sample derivatives are smoothed BEFORE taking their magnitude:
 * alternating landmark noise must not be mistaken for sustained movement.
 * Separate rotation prevents a gentle turn from lagging at the resting cutoff.
 * Coordinates are normalized by shoulder span; no anthropometric measurement.
 */
internal class AdaptivePoseMotion {
    data class Alphas(val position: Float, val shape: Float, val rotation: Float)
    private var raw: DressPose? = null
    private val velocity = FloatArray(6)
    fun reset(pose: DressPose? = null) { raw=pose; velocity.fill(0f) }

    fun coefficients(next: DressPose, dt: Float, span: Float): Alphas {
        val before=raw ?: next
        val interval=dt.coerceIn(.016f,.25f)
        fun angle(a: Float,b: Float): Float = atan2(sin(a-b),cos(a-b))
        val yaw= Math.toRadians((next.spatial?.yawDegrees ?: 0f).toDouble()).toFloat()
        val oldYaw= Math.toRadians((before.spatial?.yawDegrees ?: 0f).toDouble()).toFloat()
        val delta=floatArrayOf(
            (next.x-before.x)/span, (next.y-before.y)/span,
            ln(next.widthScale/before.widthScale), ln(next.heightScale/before.heightScale),
            angle(next.roll,before.roll), angle(yaw,oldYaw))
        val derivativeAlpha=1-exp(-2*PI.toFloat()*1f*interval)
        for(i in velocity.indices) velocity[i]+=derivativeAlpha*(delta[i]/interval-velocity[i])
        raw=next
        fun alpha(speed: Float,maxCutoff: Float,gain: Float=2.5f): Float {
            val cutoff=(.65f+gain*speed).coerceIn(.65f,maxCutoff)
            return (1-exp(-2*PI.toFloat()*cutoff*interval)).coerceIn(.04f,.95f)
        }
        return Alphas(
            // A small normalized velocity noise floor preserves stillness while
            // the stronger movement response avoids trading jitter for drag.
            alpha((hypot(velocity[0],velocity[1])-.10f).coerceAtLeast(0f),7f,16f),
            alpha(max(abs(velocity[2]),abs(velocity[3])),2.5f).coerceAtMost(.8f),
            alpha(max(abs(velocity[4]),abs(velocity[5]))*.5f,7f))
    }
}
