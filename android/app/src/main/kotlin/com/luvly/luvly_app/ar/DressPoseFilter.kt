package com.luvly.luvly_app.ar

import kotlin.math.*

data class FilteredDressPose(val pose: DressPose?, val accepted: Boolean,
                             val opacity: Float=if(pose==null)0f else 1f)

/** Time-based smoothing: quiet at rest, quicker when moving. No prediction of unseen bodies. */
class DressPoseFilter {
    var decisionReason="reset"
        private set
    val pendingObservations get()=candidateCount
    fun displayReason(now: Long): String = when {
        previous==null || lastAccepted==null -> "no_pose"
        displaySuppressed -> "suppressed"
        now-lastAccepted!! !in 0 until HIDE_AFTER_MS -> "expired"
        now-lastAccepted!!>HOLD_MS -> "fading"
        else -> "visible"
    }
    /** Read BEFORE observe; ratios/deltas only, never raw body coordinates. */
    fun diagnosticDelta(next: DressPose?,now: Long,modelShoulderWidth: Float): Map<String,Any?> {
        val old=previous
        val fields=mutableMapOf<String,Any?>("held_age_ms" to lastAccepted?.let { now-it })
        if(old!=null && next!=null) {
            fields["shift_shoulders"]=hypot(next.x-old.x,next.y-old.y)/max(35f,old.widthScale*modelShoulderWidth)
            fields["width_ratio"]=next.widthScale/old.widthScale
            fields["height_ratio"]=next.heightScale/old.heightScale
            fields["roll_delta"]=next.roll-old.roll
            if(old.spatial!=null && next.spatial!=null) {
                fields["yaw_delta"]=next.spatial.yawDegrees-old.spatial.yawDegrees
                fields["depth_ratio"]=next.spatial.shoulder.z/old.spatial.shoulder.z
            }
        }
        return fields
    }
    companion object {
        const val HOLD_MS=650L
        const val HIDE_AFTER_MS=1000L
    }
    private var previous: DressPose? = null
    private var lastAccepted: Long? = null
    private var candidate: DressPose? = null
    private var candidateSince = 0L
    private var candidateCount = 0
    private val motion = AdaptivePoseMotion()
    private var displaySuppressed=false

    fun reset() { previous=null; lastAccepted=null; candidate=null; candidateCount=0; motion.reset();displaySuppressed=false;decisionReason="reset" }

    /** Keep outlier/reacquisition history, but do not display a disproved old pose. */
    fun suppressHeldDisplay() { displaySuppressed=true }

    /** Display grace runs on UI arrival time, never on detector input/capture age.
     * Call each render tick too: a stalled camera must not leave a ghost dress.
     * A held/fading pose NEVER grants capture readiness.
     */
    fun displayAt(now: Long): FilteredDressPose {
        val last=lastAccepted ?: return FilteredDressPose(null,false)
        val age=now-last
        if(displaySuppressed || previous==null || age !in 0 until HIDE_AFTER_MS)
            return FilteredDressPose(null,false)
        val opacity=if(age<=HOLD_MS)1f else
            (HIDE_AFTER_MS-age).toFloat()/(HIDE_AFTER_MS-HOLD_MS)
        return FilteredDressPose(previous,false,opacity)
    }

    fun observe(next: DressPose?, now: Long, modelShoulderWidth: Float): FilteredDressPose {
        // Never propagate invalid transforms to Filament, even on first acquisition.
        if(next!=null && (!valid(next) || !modelShoulderWidth.isFinite() || modelShoulderWidth<=0)) {
            val result=observe(null,now,modelShoulderWidth);decisionReason="invalid_transform";return result
        }
        val old=previous
        val last=lastAccepted
        if(next==null) {
            candidate=null; candidateCount=0
            if(last==null || now-last !in 0 until HIDE_AFTER_MS)reset()
            decisionReason="missing_observation"
            return displayAt(now)
        }
        if(old==null || last==null || now-last !in 0 until HIDE_AFTER_MS || old.unprojectedWidth!=next.unprojectedWidth) {
            previous=next;lastAccepted=now;candidate=null;candidateCount=0
            motion.reset(next)
            displaySuppressed=false
            decisionReason="acquired"
            return FilteredDressPose(next,true)
        }
        val span=max(35f,old.widthScale*modelShoulderWidth)
        fun spatialJump(a: DressPose,b: DressPose): Boolean {
            val x=a.spatial ?: return false;val y=b.spatial ?: return false
            return x.right.dot(y.right)<cos(Math.toRadians(30.0)).toFloat() ||
                y.shoulder.z/x.shoulder.z !in .65f..1.55f
        }
        fun discontinuity(a: DressPose,b: DressPose): Boolean =
            hypot(a.x-b.x,a.y-b.y)>span*.85f ||
                b.widthScale/a.widthScale !in .65f..1.55f ||
                b.heightScale/a.heightScale !in .65f..1.55f || abs(a.roll-b.roll)>.5f || spatialJump(a,b)
        fun rotationOnly(a: DressPose,b: DressPose,maxShift: Float=.20f): Boolean {
            val x=a.spatial ?: return false;val y=b.spatial ?: return false
            return hypot(a.x-b.x,a.y-b.y)<span*maxShift &&
                b.widthScale/a.widthScale in .85f..1.18f &&
                b.heightScale/a.heightScale in .85f..1.18f && abs(a.roll-b.roll)<.20f &&
                y.shoulder.z/x.shoulder.z in .85f..1.18f &&
                x.right.dot(y.right)>kotlin.math.cos(Math.toRadians(100.0)).toFloat()
        }
        fun coherentTurn(first: DressPose): Boolean {
            if(!rotationOnly(old,first,.35f) || !rotationOnly(old,next,.40f) || !rotationOnly(first,next))return false
            // Two small same-direction movements may accumulate beyond 20% of
            // shoulder width. Each step is still bounded; a new translation after
            // a stationary first candidate or a reversal is not a coherent turn.
            // A low-rate frame can already move 20–35% of shoulder width during
            // a turn. Permit that first step only with a second same-direction
            // step <20%, total <40%, and the unchanged scale/depth/yaw checks.
            if(hypot(next.x-old.x,next.y-old.y)>=span*.20f) {
                val ax=first.x-old.x;val ay=first.y-old.y
                val bx=next.x-first.x;val by=next.y-first.y
                if(hypot(ax,ay)<span*.05f || ax*bx+ay*by<=0f)return false
            }
            fun yawDelta(a: DressPose,b: DressPose): Float {
                val degrees=b.spatial!!.yawDegrees-a.spatial!!.yawDegrees
                return ((degrees+540f)%360f)-180f
            }
            val initial=yawDelta(old,first)
            val step=yawDelta(first,next)
            // Two current observations along one bounded turn, not two nearly
            // identical poses. At 4 Hz a genuine turn can advance >30 deg/frame.
            // A small 3-degree reversal tolerance is for noise, not oscillation.
            return abs(initial)>=25f && abs(step)<=60f &&
                (abs(step)<=3f || initial*step>=0f)
        }
        // A single erroneous detection must not pull the gown toward a reflection.
        // A genuinely new position is accepted after three consistent observations.
        if(discontinuity(old,next)) {
            // Registration already required consecutive independently valid
            // profile fits. Do not add a second confirmation window for that same
            // bounded turn over >=250 ms. This proof cannot authorize relocation/scale/depth jumps.
            if(next.confirmedProfileTurn && now-last in 0..1000 && rotationOnly(old,next,.40f)) {
                val accepted=next.copy(confirmedProfileTurn=false)
                previous=accepted;lastAccepted=now;candidate=null;candidateCount=0
                motion.reset(accepted);displaySuppressed=false;decisionReason="registered_profile_turn"
                return FilteredDressPose(accepted,true)
            }
            val continuingTurn=candidate?.let { coherentTurn(it) } == true &&
                now-candidateSince in 100..350 && now-last<=700
            if(candidate==null || (discontinuity(candidate!!,next) && !continuingTurn)) {
                candidate=next;candidateSince=now;candidateCount=1
            } else candidateCount++
            // At 4–5 updates/s, three observations add roughly half a second.
            // Two consistent rotation-only observations may confirm a turn,
            // but never a single spike, relocation, scale jump or opposite-side flip.
            val confirmedTurn=candidateCount>=2 && continuingTurn
            if(!confirmedTurn && (candidateCount<3 || now-candidateSince<150)) {
                decisionReason="pending_confirmation"
                return displayAt(now)
            }
            previous=next;lastAccepted=now;candidate=null;candidateCount=0
            motion.reset(next)
            displaySuppressed=false
            decisionReason=if(confirmedTurn)"confirmed_turn" else "confirmed_relocation"
            return FilteredDressPose(next,true)
        }
        candidate=null;candidateCount=0
        val dt=((now-last).coerceIn(16,250)/1000f)
        val alphas=motion.coefficients(next,dt,span)
        val positionAlpha=alphas.position
        val shapeAlpha=alphas.shape
        fun mix(a: Float,b: Float,alpha: Float)=a+alpha*(b-a)
        val filtered=DressPose(mix(old.x,next.x,positionAlpha),mix(old.y,next.y,positionAlpha),
            mix(old.widthScale,next.widthScale,shapeAlpha),mix(old.heightScale,next.heightScale,shapeAlpha),
            mix(old.roll,next.roll,alphas.rotation),mix(old.waistFit,next.waistFit,shapeAlpha),
            mix(old.chestFit,next.chestFit,shapeAlpha),mix(old.hemAdjustment,next.hemAdjustment,shapeAlpha),
            if(old.spatial!=null && next.spatial!=null)old.spatial.blend(next.spatial,alphas.rotation,shapeAlpha) else next.spatial,
            next.unprojectedWidth,mix(old.shoulderTilt,next.shoulderTilt,shapeAlpha),next.confirmedProfileTurn,
            old.sleeveLeft+(next.sleeveLeft-old.sleeveLeft)*.65f,
            old.sleeveRight+(next.sleeveRight-old.sleeveRight)*.65f)
        previous=filtered;lastAccepted=now
        displaySuppressed=false
        decisionReason="smoothed"
        return FilteredDressPose(filtered,true)
    }

    private fun valid(p: DressPose): Boolean {
        if(!p.sleeveLeft.finite() || !p.sleeveRight.finite())return false
        if(listOf(p.x,p.y,p.widthScale,p.heightScale,p.roll,p.waistFit,p.chestFit,p.hemAdjustment,p.shoulderTilt)
                .any { !it.isFinite() } || p.widthScale<=0 || p.heightScale<=0)return false
        val s=p.spatial ?: return true
        return s.shoulder.finite() && s.right.finite() && s.up.finite() &&
            s.shoulder.z<-.1f && s.right.length()>.5f && s.up.length()>.5f &&
            s.widthScale.isFinite() && s.widthScale>0 && s.heightScale.isFinite() &&
            s.heightScale>0 && s.errorPixels.isFinite()
    }
}
