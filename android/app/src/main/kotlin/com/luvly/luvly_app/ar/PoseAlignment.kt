package com.luvly.luvly_app.ar

import kotlin.math.*

data class BodyPoint(val x: Float, val y: Float, val confidence: Float,
                     val z: Float=Float.NaN)
data class DressPose(val x: Float, val y: Float, val widthScale: Float,
                     val heightScale: Float, val roll: Float,
                     val waistFit: Float=0f, val chestFit: Float=0f,
                     val hemAdjustment: Float=0f,val spatial: SpatialDressPose?=null,
                     val unprojectedWidth: Boolean=false,val shoulderTilt: Float=0f,
                     val confirmedProfileTurn: Boolean=false,
                     val sleeveLeft: Vec3=Vec3(0f,0f,0f),val sleeveRight: Vec3=Vec3(0f,0f,0f))

/** Fits metre-based dress anchors to FIT_CENTER camera pixels. No fit prediction. */
object PoseAlignment {
    /** Local morph offsets: do not change overall/skirt scale or measured pose. */
    fun adjustTorso(pose: DressPose, chest: Float, waist: Float): DressPose = pose.copy(
        chestFit=(pose.chestFit+chest.coerceIn(-1f,1f)).coerceIn(0f,1f),
        waistFit=(pose.waistFit+waist.coerceIn(-1f,1f)).coerceIn(0f,1f))
    // Francine reference model coordinates in metres, not user measurements.
    const val MODEL_SHOULDER_Y=1.49f
    const val MODEL_HIP_Y=.97f
    const val MODEL_SHOULDER_WIDTH=.40f
    /** Image bounds in Android top-left coordinates, excluding FIT_CENTER bars. */
    fun imageBounds(imageW: Int,imageH: Int,viewW: Int,viewH: Int): IntArray {
        if(minOf(imageW,imageH,viewW,viewH)<=0) return intArrayOf(0,0,0,0)
        val scale=min(viewW.toFloat()/imageW,viewH.toFloat()/imageH)
        val dx=(viewW-imageW*scale)/2f
        val dy=(viewH-imageH*scale)/2f
        return intArrayOf(ceil(dx).toInt(),ceil(dy).toInt(),
            floor(viewW-dx).toInt(),floor(viewH-dy).toInt())
    }

    fun align(points: List<BodyPoint>, imageW: Int, imageH: Int,
              viewW: Int, viewH: Int, anchors: DressAnchors=DressAnchors(),
              calibratedTurn: Boolean=false, onReject: (String)->Unit={}): DressPose? {
        fun reject(reason: String): DressPose? { onReject(reason);return null }
        if (!anchors.shoulderY.isFinite() || !anchors.hipY.isFinite() ||
            !anchors.shoulderWidth.isFinite() || anchors.shoulderWidth<=0 ||
            anchors.shoulderY<=anchors.hipY) return reject("invalid_anchors")
        if (points.size < 25 || minOf(imageW,imageH,viewW,viewH) <= 0) return reject("no_body")
        val ids = listOf(11,12,23,24)
        if (ids.any { !points[it].x.isFinite() || !points[it].y.isFinite() ||
                    points[it].x !in 0f..1f || points[it].y !in 0f..1f }) return reject("out_of_frame")
        if(!TorsoVisibility.reliable(ids.map { points[it].confidence },
                calibratedTurn && TorsoVisibility.foreshortened(points,imageW,imageH)))return reject("image_confidence")
        val scale = min(viewW.toFloat()/imageW, viewH.toFloat()/imageH)
        val dx = (viewW-imageW*scale)/2
        val dy = (viewH-imageH*scale)/2
        fun p(i: Int) = Pair(dx+points[i].x*imageW*scale, viewH-(dy+points[i].y*imageH*scale))
        val a=p(11); val b=p(12); val c=p(23); val d=p(24)
        val sx=(a.first+b.first)/2; val sy=(a.second+b.second)/2
        val hx=(c.first+d.first)/2; val hy=(c.second+d.second)/2
        val shoulders=hypot(a.first-b.first,a.second-b.second)
        val torso=hypot(sx-hx,sy-hy)
        val hips=hypot(c.first-d.first,c.second-d.second)
        // Reject tiny, side-on and implausibly truncated detections.
        if (torso < 45) return reject("too_small")
        if (shoulders/torso>1.8f || sy <= hy) return reject("image_geometry")
        // Only the calibrated, world-validated path may accept a foreshortened torso.
        if (!calibratedTurn && (shoulders<35 || shoulders/torso<.45f)) return reject("front_required")
        // Joint separation is not body circumference. Bounded visual easing
        // estimates torso coverage; it must never be presented as a size result.
        val ratio=hips/max(1f,shoulders)
        val waist=if(anchors.adaptiveFit) ((ratio-.40f)/.45f).coerceIn(.15f,1f) else 0f
        val chest=if(anchors.adaptiveFit) ((ratio-.40f)/.65f).coerceIn(.15f,.65f) else 0f
        val heightScale=torso/(anchors.shoulderY-anchors.hipY)
        // When both feet are clearly visible, adjust ONLY the skirt below the hip.
        // Never stretch the bodice/neck to force the whole model into the screen.
        var hem=0f
        if(fullBodyVisible(points)) {
            val footA=p(31);val footB=p(32)
            val footX=(footA.first+footB.first)/2;val footY=(footA.second+footB.second)/2
            val visibleLeg=((hx-footX)*(sx-hx)+(hy-footY)*(sy-hy))/torso
            val restLeg=heightScale*anchors.hipY
            if(visibleLeg/torso in .85f..2.6f && restLeg>0f) {
                hem=((1-visibleLeg/restLeg)/.35f).coerceIn(-.65f,.85f)
            }
        }
        return DressPose(sx,sy,max(1f,shoulders)/anchors.shoulderWidth,
            heightScale,atan2(-(sx-hx),sy-hy),waist,chest,hem)
    }

    fun fullBodyVisible(points: List<BodyPoint>): Boolean = points.size>=33 &&
        listOf(0,27,28,31,32).all { i -> points[i].confidence>=.65f &&
            points[i].x in .03f.. .97f && points[i].y in .03f.. .97f }

    fun smooth(previous: DressPose?, next: DressPose): DressPose {
        if (previous == null) return next
        fun mix(a: Float,b: Float) = a+.35f*(b-a)
        return DressPose(mix(previous.x,next.x),mix(previous.y,next.y),
            mix(previous.widthScale,next.widthScale),mix(previous.heightScale,next.heightScale),
            mix(previous.roll,next.roll),mix(previous.waistFit,next.waistFit),
            mix(previous.chestFit,next.chestFit),mix(previous.hemAdjustment,next.hemAdjustment),
            if(previous.spatial!=null && next.spatial!=null)previous.spatial.blend(next.spatial,.35f,.35f) else next.spatial,
            next.unprojectedWidth,mix(previous.shoulderTilt,next.shoulderTilt),next.confirmedProfileTurn,
            previous.sleeveLeft+(next.sleeveLeft-previous.sleeveLeft)*.55f,
            previous.sleeveRight+(next.sleeveRight-previous.sleeveRight)*.55f)
    }
}
