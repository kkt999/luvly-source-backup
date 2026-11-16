package com.luvly.luvly_app.ar

import kotlin.math.*

/** Image-pixel capsule. This is a conservative arm core, NOT person segmentation. */
data class ArmCapsule(val ax: Float,val ay: Float,val bx: Float,val by: Float,
                      val startRadius: Float,val endRadius: Float)

object ArmOcclusion {
    fun capsules(points: List<BodyPoint>, width: Int, height: Int, radiusScale: Float=1f,
                 skinIntersection: Boolean=false): List<ArmCapsule> {
        if(points.size<25 || min(width,height)<=0)return emptyList()
        fun reliable(i: Int): Boolean = points[i].let {
            it.confidence.isFinite() && it.confidence>=.8f && it.x in .01f.. .99f &&
                it.y in .01f.. .99f && it.z.isFinite()
        }
        if(listOf(11,12).any { !reliable(it) })return emptyList()
        val fullTorso=listOf(23,24).all(::reliable)
        // A cropped torso may use observed shoulder depth, but only inside a
        // current-frame image mask. Never invent hip depth or reveal a bare capsule.
        val cropped=!fullTorso && skinIntersection && UpperBodyPreview.eligible(points,width,height)
        if(!fullTorso && !cropped)return emptyList()
        val left=points[11];val right=points[12]
        val projectedShoulders=hypot((left.x-right.x)*width,(left.y-right.y)*height)
        val shoulderY=(left.y+right.y)/2
        val hipY=if(fullTorso)(points[23].y+points[24].y)/2 else shoulderY
        if(fullTorso && hipY-shoulderY<.08f)return emptyList()
        // A conservative search region only, intersected with this frame's skin mask.
        // Torso length keeps that region usable when shoulder pixels collapse in profile.
        val shoulderPixels=if(skinIntersection)max(projectedShoulders,(hipY-shoulderY)*height*.65f)
            else projectedShoulders
        if(shoulderPixels<35)return emptyList()
        val shoulderZ=(left.z+right.z)/2
        val hipZ=if(fullTorso)(points[23].z+points[24].z)/2 else shoulderZ
        // Shoulder-plane approximation is useful near the front only. Large
        // depth separation makes a cropped torso's surface underdetermined.
        if(cropped && abs(right.z-left.z)>abs(right.x-left.x)*.8f)return emptyList()
        val depthMargin=(shoulderPixels/width*.08f).coerceIn(.018f,.06f)
        fun clearance(i: Int): Float {
            if(!reliable(i))return Float.NEGATIVE_INFINITY
            val p=points[i]
            if(cropped) {
                if(p.y !in shoulderY-projectedShoulders/height*.12f..
                        shoulderY+projectedShoulders/height*1.1f)return Float.NEGATIVE_INFINITY
                val across=((p.x-left.x)/(right.x-left.x)).coerceIn(0f,1f)
                return left.z+(right.z-left.z)*across-depthMargin-p.z
            }
            val t=((p.y-shoulderY)/(hipY-shoulderY)).coerceIn(0f,1f)
            return shoulderZ+(hipZ-shoulderZ)*t-depthMargin-p.z
        }
        fun inFront(i: Int)=clearance(i)>0f
        val result=mutableListOf<ArmCapsule>()
        for(side in 0..1) {
            val elbow=13+side;val wrist=15+side
            if(skinIntersection && inFront(elbow)) {
                val s=points[11+side];val e=points[elbow]
                val length=hypot((e.x-s.x)*width,(e.y-s.y)*height)
                if(s.z<=shoulderZ+depthMargin && length in shoulderPixels*.15f..shoulderPixels*1.3f) {
                    // Start below the shoulder, protecting the neckline from a skin cutout.
                    result.add(ArmCapsule((s.x+(e.x-s.x)*.25f)*width,(s.y+(e.y-s.y)*.25f)*height,
                        e.x*width,e.y*height,shoulderPixels*.045f*radiusScale,shoulderPixels*.035f*radiusScale))
                }
            }
            if(!reliable(elbow) || !reliable(wrist))continue
            val e=points[elbow];val w=points[wrist]
            val distance=hypot((e.x-w.x)*width,(e.y-w.y)*height)
            if(distance !in shoulderPixels*.12f..shoulderPixels*.95f)continue
            val ec=clearance(elbow);val wc=clearance(wrist)
            if(ec>0f && wc>0f) {
                result.add(ArmCapsule(e.x*width,e.y*height,w.x*width,w.y*height,
                    shoulderPixels*.043f*radiusScale,shoulderPixels*.030f*radiusScale))
            } else if(skinIntersection && (ec>0f || wc>0f)) {
                // A wrist may cross in front while the elbow remains behind.
                // Reveal only the foreground portion, intersected with skin;
                // never cut a whole forearm from a single front endpoint.
                val crossing=(-ec/(wc-ec)).coerceIn(0f,1f)
                val start=if(ec>0f)0f else (crossing+.08f).coerceAtMost(1f)
                val end=if(wc>0f)1f else (crossing-.08f).coerceAtLeast(0f)
                if(end-start>.12f) {
                    fun x(t: Float)=(e.x+(w.x-e.x)*t)*width
                    fun y(t: Float)=(e.y+(w.y-e.y)*t)*height
                    fun r(t: Float)=shoulderPixels*(.043f+(.030f-.043f)*t)*radiusScale
                    result.add(ArmCapsule(x(start),y(start),x(end),y(end),r(start),r(end)))
                }
            }
            val pinky=17+side;val index=19+side
            if(inFront(wrist) && inFront(pinky) && inFront(index)) {
                val px=(points[pinky].x+points[index].x)/2*width
                val py=(points[pinky].y+points[index].y)/2*height
                if(hypot(px-w.x*width,py-w.y*height) in shoulderPixels*.03f..shoulderPixels*.3f)
                    result.add(ArmCapsule(w.x*width,w.y*height,px,py,
                        shoulderPixels*.030f*radiusScale,shoulderPixels*.038f*radiusScale))
            }
        }
        return result
    }
}
