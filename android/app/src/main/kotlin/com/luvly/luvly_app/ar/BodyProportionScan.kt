package com.luvly.luvly_app.ar

import kotlin.math.*

/** Image-plane joint-span ratios, NOT surface widths, circumferences or cm.
 * All inputs are ephemeral. A stable window of valid samples is required.
 * No body-shape classification or anthropometric accuracy is implied. */
internal class BodyProportionScan {
    companion object {
        const val ALGORITHM_VERSION="joint-ratios-v2"
        const val MIN_SAMPLES=15
        const val MIN_DURATION_MS=3000L
        const val MAX_GAP_MS=1200L
    }
    data class Joint(val x: Double,val y: Double,val z: Double,val confidence: Double)
    data class Result(val shoulderHipRatio: Double,val torsoShoulderRatio: Double,
                      val sampleCount: Int,val durationMs: Long,val relativeSpread: Double)
    data class Update(val guidance: String,val count: Int=0,val result: Result?=null,val progress: Double=0.0)
    private data class Sample(val time: Long,val sh: Double,val ts: Double,
                              val scale: Double,val cx: Double,val cy: Double)
    private val samples=ArrayList<Sample>()
    private fun median(v: List<Double>): Double {val a=v.sorted();return if(a.size%2==0)(a[a.size/2-1]+a[a.size/2])/2 else a[a.size/2]}
    private var missed=0
    private var missedInARow=0
    private var lastProgress=0.0
    fun reset(){samples.clear();missed=0;missedInARow=0;lastProgress=0.0}
    private fun reject(reason: String): Update {reset();return Update(reason)}
    private fun pause(reason: String,time: Long): Update {
        missed++;missedInARow++
        if(samples.isEmpty() || missedInARow>2 || missed>5 ||
            time<=samples.last().time || time-samples.last().time>MAX_GAP_MS)return reject(reason)
        // No sample is added and no result is produced from an unclear frame.
        return Update(reason,samples.size,progress=lastProgress)
    }
    fun add(people: List<List<Joint>>,world: List<List<Joint>>,width: Int,height: Int,
            time: Long,brightness: Double): Update {
        if(width<=0 || height<=0 || !brightness.isFinite() || brightness<40)
            return reject("Find brighter, even lighting")
        if(people.size!=1 || world.size!=1)
            return reject(if(people.size>1) "Only one person should be in view; avoid mirrors" else "Step into view")
        val p=people[0];val w=world[0]
        // Knees are not used in either ratio. Requiring them shrinks the torso
        // in the camera and makes hip/shoulder tracking unnecessarily fragile.
        val ids=listOf(0,11,12,23,24)
        if(p.size<33 || w.size<33 || ids.any { i->
            listOf(p[i],w[i]).any { q->!q.x.isFinite() || !q.y.isFinite() || !q.z.isFinite() || !q.confidence.isFinite() } ||
            p[i].confidence<.2 || w[i].confidence<.2 || p[i].x !in .05.. .95 || p[i].y !in .04.. .96 })
            return reject("Keep your head, shoulders and hips clearly in view")
        if(ids.any { p[it].confidence<.75 || w[it].confidence<.65 })
            return pause("Keep your shoulders and hips visible; briefly checking tracking",time)
        fun dist(a: Joint,b: Joint)=hypot((a.x-b.x)*width,(a.y-b.y)*height)
        fun midpoint(a: Joint,b: Joint)=Joint((a.x+b.x)/2,(a.y+b.y)/2,0.0,1.0)
        val sl=p[11];val sr=p[12];val hl=p[23];val hr=p[24]
        val s=midpoint(sl,sr);val h=midpoint(hl,hr)
        val shoulder=dist(sl,sr);val hip=dist(hl,hr);val torso=dist(s,h)
        // Joint span is narrower than the visible shoulder outline. A stable
        // ~72px span in a 480px frame was wrongly rejected by the old 16% gate.
        // Keep pixel support checks plus the independent temporal stability gate.
        if(shoulder<width*.14 || hip<width*.08 || torso<height*.12) {
            val reason="Move a little closer; keep your head and both hips visible"
            if(shoulder<width*.12 || hip<width*.06 || torso<height*.10)return reject(reason)
            return pause(reason,time)
        }
        if(shoulder>width*.68)
            return reject("Step back a little; keep your head and both hips visible")
        val ws=w[11];val wt=w[12];val wh=w[23];val wi=w[24]
        val sw=hypot(ws.x-wt.x,ws.y-wt.y);val hw=hypot(wh.x-wi.x,wh.y-wi.y)
        // World depth is used only to reject yaw/back-facing poses, never as a ruler.
        if(sw<.05 || hw<.04 || abs(ws.z-wt.z)/sw>.28 || abs(wh.z-wi.z)/hw>.32 ||
            w[0].z>=(ws.z+wt.z)/2-.025 ||
            p[0].x !in min(sl.x,sr.x)..max(sl.x,sr.x))
            return reject("Face the camera straight on")
        if(h.y<=s.y || abs((sl.y-sr.y)*height)/shoulder>.18 ||
            abs((hl.y-hr.y)*height)/hip>.20 || abs((h.x-s.x)*width)/torso>.16)
            return reject("Stand upright; keep the phone level and fixed")
        val sh=shoulder/hip;val ts=torso/shoulder
        if(sh !in .6..2.4 || ts !in .5..2.6)
            return reject("Adjust your position and try again")
        if(samples.isNotEmpty() && (time<=samples.last().time || time-samples.last().time>MAX_GAP_MS))reset()
        // Store actual image centres. Dividing a centre by each noisy width
        // falsely turns width jitter into a translation, especially off-centre.
        val sample=Sample(time,sh,ts,shoulder,s.x*width,s.y*height)
        if(samples.isNotEmpty()) {
            // A robust recent reference avoids treating normal breathing or one
            // noisy first landmark as a permanent camera-motion baseline.
            val recent=samples.takeLast(7)
            val referenceScale=median(recent.map{it.scale})
            // Symmetric relative change avoids asymmetric boundary flips for
            // equally sized +3%/-3% landmark jitter around a stationary body.
            val scaleChange=abs(shoulder-referenceScale)/maxOf(shoulder,referenceScale)
            val centreChange=hypot(sample.cx-median(recent.map{it.cx}),sample.cy-median(recent.map{it.cy}))/referenceScale
            val reason="Hold still briefly; keep the phone fixed"
            if(scaleChange>.10 || centreChange>.18)return reject(reason)
            if(scaleChange>.06 || centreChange>.12)return pause(reason,time)
        }
        missedInARow=0
        samples.add(sample)
        if(samples.size>90 || time-samples.first().time>15000) {
            reset();samples.add(sample)
        }
        // Require enough real high-quality samples AND elapsed evidence, rather
        // than assuming every phone can produce 30 frames in two seconds.
        val duration=time-samples.first().time
        if(samples.size<MIN_SAMPLES || duration<MIN_DURATION_MS) {
            lastProgress=minOf(samples.size.toDouble()/MIN_SAMPLES,duration.toDouble()/MIN_DURATION_MS,.95)
            return Update("Hold still while we check your proportions",samples.size,progress=lastProgress)
        }
        val shm=median(samples.map{it.sh});val tsm=median(samples.map{it.ts})
        val scale=median(samples.map{it.scale})
        val centreX=median(samples.map{it.cx});val centreY=median(samples.map{it.cy})
        val positionSpread=median(samples.map{hypot(it.cx-centreX,it.cy-centreY)})/scale
        // Robust relative median absolute deviation measures repeatability, not accuracy.
        val spread=maxOf(median(samples.map{abs(it.sh-shm)})/shm,
            median(samples.map{abs(it.ts-tsm)})/tsm,median(samples.map{abs(it.scale-scale)})/scale)
        // MAD alone can hide a bimodal sequence with an odd sample count.
        fun upper(v: List<Double>)=v.sorted()[ceil((v.size-1)*.8).toInt()]
        val tail=maxOf(upper(samples.map{abs(it.sh-shm)})/shm,
            upper(samples.map{abs(it.ts-tsm)})/tsm,upper(samples.map{abs(it.scale-scale)})/scale)
        val positionTail=upper(samples.map{hypot(it.cx-centreX,it.cy-centreY)})/scale
        // Check the WHOLE window too: a rolling reference must not allow a
        // gradual walk/phone drift to masquerade as stationary evidence.
        if(spread>.035 || tail>.07 || positionSpread>.06 || positionTail>.12) {
            // Entry/settling frames should age out, not erase all the clearer
            // evidence that followed. A result still needs a complete stable
            // duration after this trim; sustained movement never completes.
            val keep=maxOf(MIN_SAMPLES-1,samples.size/2).coerceAtMost(samples.size-1)
            while(samples.size>keep)samples.removeAt(0)
            lastProgress=minOf(samples.size.toDouble()/MIN_SAMPLES,
                (time-samples.first().time).toDouble()/MIN_DURATION_MS,.95)
            return Update("Keep still; refining your scan",samples.size,progress=lastProgress)
        }
        lastProgress=1.0
        return Update("Scan ready to review",samples.size,
            Result(shm,tsm,samples.size,duration,spread),progress=1.0)
    }
}
