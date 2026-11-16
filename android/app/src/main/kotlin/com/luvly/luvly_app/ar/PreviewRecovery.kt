package com.luvly.luvly_app.ar

/** A bounded retry for the timer boundary; caller still verifies live readiness. */
class PreviewRecovery(private val startedAt: Long) {
    fun canCapture(now: Long, freshPoseReady: Boolean): Boolean =
        freshPoseReady && now-startedAt in 0 until 3000
}
