package com.luvly.luvly_app.ar

import kotlin.math.*

/** Session-only geometric continuity, NOT identity/face or reflection recognition.
 * Never transfers a lost lock to a different location automatically. The caller
 * serializes select/reset and rejects results from old camera/reset generations.
 */
internal class BodyTargetLock {
    data class Selection(val index: Int?,val reason: String,val resetAlignment: Boolean=false,
                         val retainCalibration: Boolean=false)
    private data class Torso(val index: Int,val x: Float,val y: Float,val height: Float,val front: Boolean,
                             val sx: Float,val sy: Float,val span: Float,val upper: Boolean=false)
    private data class Pending(val torso: Torso,val since: Long,val at: Long,val count: Int,
                               val retainCalibration: Boolean)
    private var locked: Torso?=null
    private var lastSeen: Long?=null
    private var pending: Pending?=null
    private var lastFrame: Long?=null
    private var ambiguousSinceSeen=false
    fun reset() { locked=null;lastSeen=null;pending=null;lastFrame=null;ambiguousSinceSeen=false }

    /** The detector can emit two crops of the same pose. Require overlap of
     * corresponding face and torso landmarks, not just similar torso centres. */
    private fun overlappingLandmarks(a: List<BodyPoint>, b: List<BodyPoint>,
                                     aspect: Float, torsoLength: Float): Boolean {
        fun near(index: Int, minimumConfidence: Float, tolerance: Float): Boolean {
            val p=a[index]
            val q=b[index]
            return p.confidence.isFinite() && q.confidence.isFinite() &&
                min(p.confidence,q.confidence)>=minimumConfidence &&
                p.x in 0f..1f && p.y in 0f..1f && q.x in 0f..1f && q.y in 0f..1f &&
                hypot((p.x-q.x)*aspect,p.y-q.y)<=torsoLength*tolerance
        }
        return near(0,.75f,.06f) && near(2,.75f,.06f) && near(5,.75f,.06f) &&
            listOf(11,12,23,24).all { near(it,.65f,.13f) }
    }

    fun select(people: List<List<BodyPoint>>,width: Int,height: Int,now: Long): Selection {
        if(lastFrame?.let { now<=it }==true) {
            // Repeated/stale timestamps must neither accumulate confirmation nor
            // clear a retained target and permit an unintended transfer.
            pending=null
            ambiguousSinceSeen=true
            return Selection(null,"target_stale")
        }
        lastFrame=now
        fun descriptor(index: Int,p: List<BodyPoint>): Torso? {
            if(width<=0 || height<=0 || p.size<25)return null
            val aspect=width.toFloat()/height
            val sx=(p[11].x+p[12].x)*aspect/2;val sy=(p[11].y+p[12].y)/2
            val shoulderSpan=hypot((p[11].x-p[12].x)*aspect,p[11].y-p[12].y)
            if(UpperBodyPreview.eligible(p,width,height))
                return Torso(index,sx,sy+shoulderSpan*.65f,shoulderSpan*1.3f,true,
                    sx,sy,shoulderSpan,true)
            val joints=listOf(p[11],p[12],p[23],p[24])
            if(joints.any { !it.confidence.isFinite() || it.confidence<.45f ||
                    !it.x.isFinite() || !it.y.isFinite() || it.x !in 0f..1f || it.y !in 0f..1f })return null
            val hx=(p[23].x+p[24].x)*aspect/2;val hy=(p[23].y+p[24].y)/2
            val length=hypot(hx-sx,hy-sy)
            if(length !in .07f.. .65f || hy<=sy)return null
            return Torso(index,(sx+hx)/2,(sy+hy)/2,length,
                joints.all { it.confidence>=.65f } && shoulderSpan/length>=.45f,sx,sy,shoulderSpan)
        }
        val candidates=people.mapIndexedNotNull { i,p->descriptor(i,p) }
        val old=locked
        fun distance(a: Torso,b: Torso)=if(a.upper || b.upper)
            hypot(a.sx-b.sx,a.sy-b.sy)/max(.05f,a.span*1.3f)
            else hypot(a.x-b.x,a.y-b.y)/a.height
        fun ratio(a: Torso,b: Torso)=if(a.upper || b.upper)b.span/a.span else b.height/a.height
        fun similar(a: Torso,b: Torso,limit: Float)=
            ratio(a,b) in .70f..1.40f && distance(a,b)<limit
        fun reject(reason: String): Selection {
            pending=null
            if(reason=="target_ambiguous")ambiguousSinceSeen=true
            return Selection(null,reason)
        }
        val continuing=lastSeen?.let { now-it in 1..600 }==true
        val chosen: Torso
        if(old==null) {
            val aspect=width.toFloat()/max(1,height)
            val ranked=candidates.filter { it.front && abs(it.x/aspect-.5f)<=.20f }
                .sortedBy { abs(it.x-aspect*.5f)/it.height }
            chosen=ranked.firstOrNull() ?: return reject("target_centre_required")
            if(ranked.size>1 && abs(ranked[1].x-aspect*.5f)/ranked[1].height-
                    abs(chosen.x-aspect*.5f)/chosen.height<.30f)return reject("target_ambiguous")
        } else {
            val ranked=candidates.filter { similar(old,it,.55f) }.sortedBy { distance(old,it) }
            chosen=ranked.firstOrNull() ?: return reject("target_lost")
            if(ranked.size>1 && distance(old,ranked[1])-distance(old,chosen)<.30f) {
                val duplicate=ranked.size==2 && continuing && !ambiguousSinceSeen &&
                    distance(old,chosen)<.20f && ratio(old,chosen) in .80f..1.20f &&
                    overlappingLandmarks(people[chosen.index],people[ranked[1].index],
                        width.toFloat()/height,min(chosen.height,ranked[1].height))
                if(!duplicate)return reject("target_ambiguous")
            }
            // During uninterrupted tracking the nearest coherent target remains
            // selected even if a reflection becomes more central or confident.
            if(continuing) {
                locked=chosen;lastSeen=now;pending=null;ambiguousSinceSeen=false
                return Selection(chosen.index,"target_tracked")
            }
        }
        // Accumulate fresh fast frames too; the 250 ms evidence window below
        // still prevents a burst of detections from confirming immediately.
        val previous=pending?.takeIf { now-it.at in 1..650 && now-it.since<=1500 && similar(it.torso,chosen,.25f) }
        // Preserve only session geometry after a short, tightly matched return.
        // All three confirmation observations must pass; no identity claim is made.
        val retain=old!=null && !ambiguousSinceSeen && lastSeen?.let { now-it in 1..1800 }==true &&
            distance(old,chosen)<.20f && ratio(old,chosen) in .90f..1.10f &&
            (previous?.retainCalibration ?: true)
        val next=Pending(chosen,previous?.since ?: now,now,(previous?.count ?: 0)+1,retain)
        pending=next
        if(next.count<3 || now-next.since<250)
            return Selection(null,if(old==null)"target_confirming" else "target_reconfirming")
        locked=chosen;lastSeen=now;pending=null;ambiguousSinceSeen=false
        return Selection(chosen.index,if(old==null)"target_acquired" else "target_reacquired",true,retain)
    }
}
