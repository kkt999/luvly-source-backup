package com.luvly.luvly_app.ar

/** Display-only grace for single missed detections. Never grants capture readiness. */
class PoseDisplayHold {
    private var lastValid = Long.MIN_VALUE
    fun observe(valid: Boolean, now: Long): Boolean {
        if (valid) lastValid = now
        return valid || (lastValid != Long.MIN_VALUE && now - lastValid in 0..300)
    }
}
