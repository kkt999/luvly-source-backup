package com.luvly.luvly_app.ar

import kotlin.math.*

/** A bounded weak-perspective cross-check for an already tracked profile.
 * Fits ONE positive scale and translation to all four current world XY/image
 * pairs. No independent joint warping, mirrored scale, or invented landmarks.
 * Used only when approximate lens/depth perspective fails; not measured depth.
 */
object ProfileImageFit {
    data class Fit(val scale: Float,val error: Float)
    fun fit(world: List<Vec3>,pixels: List<Pair<Float,Float>>,torsoPixels: Float): Fit? {
        if(world.size!=4 || pixels.size!=4 || !torsoPixels.isFinite() || torsoPixels<45 ||
            world.any { !it.finite() } || pixels.any { !it.first.isFinite() || !it.second.isFinite() })return null
        val wx=world.map { it.x }.average().toFloat();val wy=world.map { it.y }.average().toFloat()
        val px=pixels.map { it.first }.average().toFloat();val py=pixels.map { it.second }.average().toFloat()
        var numerator=0f;var denominator=0f
        for(i in world.indices) {
            val x=world[i].x-wx;val y=world[i].y-wy
            numerator+=x*(pixels[i].first-px)+y*(pixels[i].second-py)
            denominator+=x*x+y*y
        }
        if(denominator<1e-5f)return null
        val scale=numerator/denominator
        if(!scale.isFinite() || scale<=0)return null
        val errors=world.indices.map { i->hypot(px+scale*(world[i].x-wx)-pixels[i].first,
            py+scale*(world[i].y-wy)-pixels[i].second) }
        val rms=sqrt(errors.map { it*it }.average().toFloat())
        // Bound both aggregate and worst-joint error; a good mean cannot mask a bad hip.
        if(rms>max(6f,torsoPixels*.10f) || errors.maxOrNull()!!>max(10f,torsoPixels*.16f))return null
        return Fit(scale,rms)
    }
}
