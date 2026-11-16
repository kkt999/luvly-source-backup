package com.luvly.luvly_app.ar

import kotlin.math.*

/** Visual fitting only: not circumference estimation or cloth physics. */
internal class BodiceFit {
    private var waist: Float?=null
    private var chest=0f
    private var tilt=0f
    fun reset() { waist=null;chest=0f;tilt=0f }

    fun apply(pose: DressPose,points: List<BodyPoint>,width: Int,height: Int,anchors: DressAnchors,
              world: List<WorldBodyPoint> = emptyList()): DressPose {
        if(!anchors.adaptiveFit)return pose
        val yaw=abs(pose.spatial?.yawDegrees ?: 90f)
        // Only accepted near-front observations may refine body proportions.
        // Noisy profile world-joint widths must not inflate/deflate the bodice.
        if(yaw<=25f && pose.waistFit.isFinite() && pose.chestFit.isFinite()) {
            if(waist==null) { waist=pose.waistFit;chest=pose.chestFit }
            else { waist=waist!!+.04f*(pose.waistFit-waist!!);chest+=.04f*(pose.chestFit-chest) }
        }
        val measured=shoulderTilt(pose,points,width,height,anchors)
        // At a profile the shoulder slope is underdetermined; retain the last
        // reliable local correction instead of amplifying near-zero separation.
        if(measured!=null)tilt+=.25f*(measured-tilt)
        val sleeves=SleeveFit.offsets(pose,world,points)
        return pose.copy(waistFit=waist ?: pose.waistFit,chestFit=if(waist==null)pose.chestFit else chest,
            shoulderTilt=tilt,sleeveLeft=sleeves.first,sleeveRight=sleeves.second)
    }

    companion object {
        /** Signed weight for y += .18*x*upperBodiceFalloff in model space. */
        fun shoulderTilt(p: DressPose,points: List<BodyPoint>,width: Int,height: Int,a: DressAnchors): Float? {
            if(points.size<25 || min(width,height)<=0 || a.shoulderWidth<=0 || abs(p.spatial?.yawDegrees ?: 90f)>45f)return null
            val l=points[11];val r=points[12]
            if(listOf(l,r).any { it.confidence<.8f || !it.confidence.isFinite() ||
                    !it.x.isFinite() || !it.y.isFinite() || it.x !in 0f..1f || it.y !in 0f..1f })return null
            val dx=abs(r.x-l.x)*width
            if(dx<35f || p.heightScale<=0 || p.widthScale<=0)return null
            val yaw=Math.toRadians((p.spatial?.yawDegrees ?: 0f).toDouble()).toFloat()
            // A perspective camera projects equal-height shoulders to different
            // image Y positions during yaw. Use the validated 3D shoulder axis,
            // not that image slope, or a normal turn becomes a false shrug.
            val axis=p.spatial?.right ?: return null
            if(!axis.finite())return null
            val localX=cos(p.roll)*axis.x+sin(p.roll)*axis.y
            val localY=-sin(p.roll)*axis.x+cos(p.roll)*axis.y
            if(localX<=0)return null
            val widthScale=if(p.unprojectedWidth)p.widthScale else p.widthScale/cos(yaw)
            return (localY/localX*cos(yaw)*widthScale/p.heightScale/.18f).coerceIn(-1f,1f)
        }
    }
}
