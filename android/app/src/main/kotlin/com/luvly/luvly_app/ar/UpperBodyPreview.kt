package com.luvly.luvly_app.ar

import kotlin.math.*

/** Cropped, front-facing appearance preview. Unseen hips are never measurements.
 * Uses current shoulders and world shoulder orientation; model proportions (or
 * a recent full-torso fit from this target) supply the unseen garment length. */
internal class UpperBodyPreview {
    companion object {
        const val MODE="upper-body-preview"
        fun isUpper(pose: DressPose?)=pose?.spatial?.registrationMode==MODE

        fun eligible(p: List<BodyPoint>, width: Int, height: Int): Boolean {
            if(p.size<25 || min(width,height)<=0)return false
            fun visible(i: Int)=p[i].confidence.isFinite() && p[i].confidence>=.65f &&
                p[i].x in .02f.. .98f && p[i].y in .02f.. .98f
            if(!listOf(0,2,5,11,12).all(::visible))return false
            val a=p[11];val b=p[12];val nose=p[0]
            val aspect=width.toFloat()/height
            val span=hypot((b.x-a.x)*aspect,b.y-a.y)
            val sx=(a.x+b.x)/2;val sy=(a.y+b.y)/2
            if(abs(b.x-a.x)<.30f || sy !in .15f.. .72f ||
                abs(b.y-a.y)>span*.35f)return false
            // A face must sit above and between two visible shoulders. A close
            // face alone, back view or occluded shoulder cannot place a gown.
            if((sy-nose.y)/span !in .12f..1.15f || abs(nose.x-sx)*aspect>span*.55f)return false
            val hips=listOf(p[23],p[24])
            if(hips.all { it.confidence.isFinite() && it.confidence>=.65f &&
                    it.x in 0f..1f && it.y in 0f.. .96f })return false
            // Only a bottom crop qualifies. Missing hips in the middle of an
            // otherwise full-body frame must not bypass normal tracking checks.
            return hips.all { it.y.isFinite() && it.y>=.96f } ||
                (hips.all { it.confidence.isFinite() && it.confidence<.65f } && sy+span*1.3f>=.90f)
        }
    }

    private var reference: DressPose?=null
    private var referenceAt=0L
    fun reset() { reference=null;referenceAt=0 }
    fun remember(pose: DressPose, now: Long) {
        if(!isUpper(pose) && pose.unprojectedWidth && pose.spatial!=null &&
            abs(pose.spatial.yawDegrees)<25 && pose.heightScale/pose.widthScale in .5f..2f) {
            reference=pose;referenceAt=now
        }
    }

    fun register(points: List<BodyPoint>,world: List<WorldBodyPoint>,imageW: Int,imageH: Int,
                 viewW: Int,viewH: Int,anchors: DressAnchors,frame: FrameProjection,now: Long): DressPose? {
        if(!eligible(points,imageW,imageH) || world.size<13 || min(viewW,viewH)<=0 ||
            frame.width!=imageW || frame.height!=imageH || anchors.shoulderWidth<=0)return null
        if(listOf(11,12).any { !world[it].confidence.isFinite() || world[it].confidence<.65f ||
                !world[it].cameraVector().finite() })return null
        val order=if(points[12].x>points[11].x)1f else -1f
        val axis=(world[12].cameraVector()-world[11].cameraVector())*order
        if(axis.length() !in .18f.. .75f)return null
        val right=axis.unit() ?: return null
        val yaw=atan2(-right.z,right.x)
        if(abs(yaw)>Math.toRadians(45.0) || abs(right.y)>.4f)return null
        val vertical=Vec3(0f,1f,0f)
        val up=(vertical-right*vertical.dot(right)).unit() ?: return null
        val projection=frame.forView(viewW,viewH) ?: return null
        val scale=min(viewW.toFloat()/imageW,viewH.toFloat()/imageH)
        val a=points[11];val b=points[12]
        val sx=(viewW-imageW*scale)/2+(a.x+b.x)*imageW*scale/2
        val sy=viewH-(viewH-imageH*scale)/2-(a.y+b.y)*imageH*scale/2
        val dx=(b.x-a.x)*imageW*scale*order
        val dy=-(b.y-a.y)*imageH*scale*order
        val span=hypot(dx,dy)
        if(span<45)return null
        val width=span/(cos(yaw)*anchors.shoulderWidth)
        val saved=reference?.takeIf { now-referenceAt in 0..5000 }
        val height=width*(saved?.let { it.heightScale/it.widthScale } ?: 1f)
        // Approximate depth is used for continuity diagnostics only. Rendering
        // remains anchored to the observed image, like the full-torso renderer.
        val depth=projection.fx*axis.length()*cos(yaw)/span
        if(depth !in .25f..8f)return null
        val spatial=SpatialDressPose(Vec3((sx-projection.cx)*depth/projection.fx,
            (sy-projection.cy)*depth/projection.fy,-depth),right,up,
            axis.length()/anchors.shoulderWidth,axis.length()/anchors.shoulderWidth,
            projection,0f,MODE,Float.NaN)
        val pose=DressPose(sx,sy,width,height,atan2(dy,dx),
            waistFit=saved?.waistFit ?: 0f,chestFit=saved?.chestFit ?: 0f,
            hemAdjustment=saved?.hemAdjustment ?: 0f,spatial=spatial,unprojectedWidth=true)
        if(!anchors.adaptiveFit)return pose
        // The visible shoulder/elbow pair can articulate the wrap even when
        // hips are cropped. Unseen chest and waist proportions stay unchanged.
        val sleeves=SleeveFit.offsets(pose,world,points)
        return pose.copy(sleeveLeft=sleeves.first,sleeveRight=sleeves.second)
    }
}
