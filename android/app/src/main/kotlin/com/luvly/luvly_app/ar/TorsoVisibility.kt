package com.luvly.luvly_app.ar

import kotlin.math.hypot

/** Only a foreshortened, front-calibrated torso may use partly occluded landmarks.
 * Scores are detector confidence, not probabilities or body measurements.
 * No joints are invented: all four must still have finite in-frame observations.
 */
object TorsoVisibility {
    fun reliable(scores: List<Float>, partialProfile: Boolean): Boolean {
        if(scores.size!=4 || scores.any { !it.isFinite() || it !in 0f..1f })return false
        if(scores.all { it>=.65f })return true
        if(!partialProfile || scores.any { it<.45f })return false
        val shoulders=scores.take(2);val hips=scores.drop(2)
        return (shoulders.all { it>=.8f } && hips.maxOrNull()!!>=.6f) ||
            (hips.all { it>=.8f } && shoulders.maxOrNull()!!>=.6f)
    }

    fun foreshortened(points: List<BodyPoint>, w: Int,h: Int): Boolean {
        if(points.size<25 || w<=0 || h<=0)return false
        val a=points[11];val b=points[12];val c=points[23];val d=points[24]
        if(listOf(a,b,c,d).any { !it.x.isFinite() || !it.y.isFinite() || it.x !in 0f..1f || it.y !in 0f..1f })return false
        val torso=hypot((a.x+b.x-c.x-d.x)*w/2,(a.y+b.y-c.y-d.y)*h/2)
        return torso>0 && hypot((a.x-b.x)*w,(a.y-b.y)*h)/torso<.55f
    }
}
