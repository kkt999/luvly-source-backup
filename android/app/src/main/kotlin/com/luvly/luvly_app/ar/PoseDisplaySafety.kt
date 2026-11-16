package com.luvly.luvly_app.ar

import kotlin.math.*

/** Fresh image evidence can disprove a held pose without being enough for a new
 * 3D fit. Hide that stale overlay; never promote these points to a render pose.
 */
object PoseDisplaySafety {
    fun shouldHide(held: DressPose?,points: List<BodyPoint>,imageW: Int,imageH: Int,
                   viewW: Int,viewH: Int,anchors: DressAnchors): Boolean =
        hideReason(held,points,imageW,imageH,viewW,viewH,anchors)!=null

    fun hideReason(held: DressPose?,points: List<BodyPoint>,imageW: Int,imageH: Int,
                   viewW: Int,viewH: Int,anchors: DressAnchors): String? {
        if(held==null || points.size<25 || minOf(imageW,imageH,viewW,viewH)<=0)return null
        val a=points[11];val b=points[12]
        if(listOf(a,b).any { !it.confidence.isFinite() || it.confidence<.65f ||
                !it.x.isFinite() || !it.y.isFinite() })return null
        val upper=UpperBodyPreview.isUpper(held)
        val all=if(upper)listOf(a,b) else listOf(a,b,points[23],points[24])
        if(all.any { it.confidence>=.45f && (it.x !in 0f..1f || it.y !in 0f..1f) })return "body_out_of_frame"
        val scale=min(viewW.toFloat()/imageW,viewH.toFloat()/imageH)
        val x=(viewW-imageW*scale)/2+(a.x+b.x)*imageW*scale/2
        val y=viewH-((viewH-imageH*scale)/2+(a.y+b.y)*imageH*scale/2)
        val span=max(35f,held.widthScale*anchors.shoulderWidth)
        if(hypot(x-held.x,y-held.y)>span*.20f)return "shoulder_position_changed"
        if(upper) {
            val observedSpan=hypot((a.x-b.x)*imageW*scale,(a.y-b.y)*imageH*scale)
            val oldSpan=held.widthScale*anchors.shoulderWidth*cos(Math.toRadians(held.spatial!!.yawDegrees.toDouble())).toFloat()
            if(oldSpan>0 && observedSpan/oldSpan !in .80f..1.25f)return "shoulder_scale_changed"
        }
        if(!upper && all.all { it.confidence>=.65f && it.x.isFinite() && it.y.isFinite() }) {
            val c=points[23];val d=points[24]
            val torso=hypot((a.x+b.x-c.x-d.x)*imageW*scale/2,
                (a.y+b.y-c.y-d.y)*imageH*scale/2)
            val oldTorso=held.heightScale*(anchors.shoulderY-anchors.hipY)
            if(oldTorso>0 && torso/oldTorso !in .80f..1.25f)return "torso_scale_changed"
        }
        return null
    }
}
