package com.luvly.luvly_app.ar

/** Actionable framing hints only. Visibility is a detector score, never a fit score.
 * Does not relax registration, readiness, or saving requirements.
 */
object PoseGuidance {
    enum class Issue(val message: String) {
        NO_BODY("Stand in view · Keep shoulders and hips visible"),
        CLIPPED("Move toward the centre · Keep your shoulders and hips inside the frame"),
        SHOULDERS("Keep both shoulders visible · Uncover them and face the camera"),
        HIPS("Keep both hips visible · Step back or lower the camera slightly"),
        TOO_FAR("Move a little closer · Your upper body is too small to track"),
        TURN("Turn slightly toward the camera · Keep your torso visible"),
        POSTURE("Stand upright · Keep your phone level and torso in view"),
        CLEAR("")
    }
    fun assess(points: List<BodyPoint>, imageW: Int,imageH: Int,viewW: Int,viewH: Int): Issue {
        if(points.size<25 || minOf(imageW,imageH,viewW,viewH)<=0)return Issue.NO_BODY
        val ids=listOf(11,12,23,24)
        if(ids.any { !points[it].x.isFinite() || !points[it].y.isFinite() })return Issue.NO_BODY
        if(ids.any { points[it].x !in .02f.. .98f || points[it].y !in .02f.. .98f })return Issue.CLIPPED
        fun visible(i: Int)=points[i].confidence.isFinite() && points[i].confidence>=.65f
        if(!visible(11) || !visible(12))return Issue.SHOULDERS
        if(!visible(23) || !visible(24))return Issue.HIPS
        val scale=minOf(viewW.toFloat()/imageW,viewH.toFloat()/imageH)
        val shoulders=kotlin.math.hypot((points[11].x-points[12].x)*imageW*scale,
            (points[11].y-points[12].y)*imageH*scale)
        val dx=(points[11].x+points[12].x-points[23].x-points[24].x)*imageW*scale/2
        val dy=(points[23].y+points[24].y-points[11].y-points[12].y)*imageH*scale/2
        val torso=kotlin.math.hypot(dx,dy)
        if(torso<45)return Issue.TOO_FAR
        if(dy<=0 || shoulders/torso>1.8f)return Issue.POSTURE
        if(shoulders<35 || shoulders/torso<.45f)return Issue.TURN
        return Issue.CLEAR
    }
}
