package com.luvly.luvly_app.ar

/** Optional skin segmentation must not dominate a slow phone's live tracker.
 * Warm-up is excluded; disable only after sustained expensive mask work.
 */
class LiveRefinementBudget {
    private var attempts=0
    private var slow=0
    var enabled=true
        private set
    fun observe(beforeMaskMs: Long,maskMs: Long) {
        if(beforeMaskMs<0 || maskMs<0 || !enabled)return
        attempts++
        if(attempts<=2)return
        slow=if(maskMs>60 && beforeMaskMs+maskMs>140)slow+1 else 0
        if(slow>=3)enabled=false
    }
}

data class FrameTimings(val preparationMs: Long,val poseMs: Long,val armsMs: Long,val armsMode: String,
                       val poseBackend: String="unknown",val poseModel: String="unknown")
