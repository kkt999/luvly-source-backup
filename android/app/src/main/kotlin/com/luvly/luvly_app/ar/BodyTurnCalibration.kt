package com.luvly.luvly_app.ar

import kotlin.math.*

/** Session-local visual proportions, not body measurements. No frames are stored.
 * Establish left/right ordering from a front view before accepting profile views.
 * Use torso length for scale on turns: dividing shoulder pixels by cos(90) is singular.
 */
class BodyTurnCalibration {
    private val bodiceFit=BodiceFit()
    private var order: Float?=null
    private var widthPerHeight=0f
    private var worldRatio=0f
    private var frontCount=0
    private var frontSince=0L
    private var lastValid: Long?=null
    private var lastYaw=0f
    private var lastImagePose: DressPose?=null
    private data class ProfileCandidate(val pose: DressPose,val at: Long,val since: Long,val count: Int)
    private var profileCandidate: ProfileCandidate?=null
    var rejectionReason="front_required"
        private set
    val ready get()=order!=null && frontCount>=3
    /** No pose is emitted while target selection is blocked. Keep the old
     * calibration briefly for a separately confirmed return, without extending
     * lastValid or retaining candidate evidence. Long absences still expire. */
    fun pauseForTarget(now: Long) {
        profileCandidate=null
        if(lastValid?.let { now-it !in 0..2000 }==true)reset()
        rejectionReason="target_unconfirmed"
    }
    fun reset() { bodiceFit.reset();order=null;widthPerHeight=0f;worldRatio=0f;frontCount=0;frontSince=0;lastValid=null;lastYaw=0f;lastImagePose=null;profileCandidate=null;rejectionReason="front_required" }

    fun register(points: List<BodyPoint>,world: List<WorldBodyPoint>,
                 imageW: Int,imageH: Int,viewW: Int,viewH: Int,
                 anchors: DressAnchors,frame: FrameProjection,now: Long): DressPose? {
        // Pending evidence is consecutive: any other rejection/accepted mode clears it.
        val pendingProfile=profileCandidate
        profileCandidate=null
        // Calibration may survive a short visible-body interruption, while the
        // renderer independently hides stale poses after <=1 s. Never extend this
        // deadline from rejected observations or retain it across an unseen body.
        val evidence=if(ready)PoseAlignment.align(points,imageW,imageH,viewW,viewH,anchors,true) else null
        fun continuous(p: DressPose?): Boolean {
            val previous=lastImagePose ?: return false
            if(p==null)return false
            val torso=previous.heightScale*(anchors.shoulderY-anchors.hipY)
            return p.heightScale/previous.heightScale in .8f..1.25f &&
                hypot(p.x-previous.x,p.y-previous.y)<torso*.4f
        }
        val bodyContinuous=continuous(evidence)
        lastValid?.let {
            val age=now-it
            if(age !in 0..5000 || (age>1500 && !bodyContinuous))reset()
        }
        fun reject(reason: String): DressPose? { rejectionReason=reason;return null }
        rejectionReason="none"
        val base=PoseAlignment.align(points,imageW,imageH,viewW,viewH,anchors,ready) { rejectionReason=it } ?: return null
        val recovery=ready && bodyContinuous && lastValid?.let { now-it in 0..5000 }==true
        val profileTolerance=recovery && abs(lastYaw)>=55f && TorsoVisibility.foreshortened(points,imageW,imageH)
        val pose=BodyRegistration3D.register(base,points,world,imageW,imageH,viewW,viewH,
            anchors,frame,if(ready)order else null,profileTolerance,recovery) { rejectionReason=it } ?: return null
        val spatial=pose.spatial ?: return reject("missing_spatial")
        val yaw=abs(spatial.yawDegrees)
        if(profileTolerance && yaw>92f && abs(spatial.yawDegrees-lastYaw)>25f)return reject("turn_jump")
        val ratio=spatial.widthScale/spatial.heightScale
        if(!ratio.isFinite() || ratio<=0)return reject("invalid_ratio")
        if(ready && ratio/worldRatio !in .70f..1.40f)return reject("proportion_change")

        var confirmedProfileTurn=false
        if(spatial.registrationMode=="image-anchored-profile" && abs(spatial.yawDegrees-lastYaw)>35f) {
            // A valid profile must not be permanently compared against a stale front
            // angle. Confirm current independent fits over at least 250 ms; do not update lastValid
            // or lastYaw from rejected candidates, or relax world/image/back-view gates.
            if(!recovery || yaw>92f || (abs(lastYaw)>=25f && lastYaw*spatial.yawDegrees<0f))
                return reject("profile_recovery_jump")
            fun coherent(previous: DressPose): Boolean {
                val s=previous.spatial ?: return false
                val torso=previous.heightScale*(anchors.shoulderY-anchors.hipY)
                return s.yawDegrees*spatial.yawDegrees>0f &&
                    abs(s.yawDegrees-spatial.yawDegrees)<=25f &&
                    hypot(previous.x-pose.x,previous.y-pose.y)<torso*.20f &&
                    pose.heightScale/previous.heightScale in .85f..1.18f &&
                    spatial.widthScale/s.widthScale in .85f..1.18f &&
                    spatial.shoulder.z/s.shoulder.z in .85f..1.18f &&
                    abs(previous.roll-pose.roll)<.20f
            }
            // Fresh observations can arrive faster than 80 ms. Evidence duration,
            // not a minimum inter-frame delay, prevents premature confirmation.
            // Keep duplicate timestamps and long gaps excluded.
            val prior=pendingProfile?.takeIf { now-it.at in 1..350 && now-it.since in 0..800 && coherent(it.pose) }
            val candidate=ProfileCandidate(pose,now,prior?.since ?: now,(prior?.count ?: 0)+1)
            // At the observed ~3 Hz, two coherent observations already span
            // 250 ms. A fixed three-frame gate adds an unnecessary extra frame.
            // Faster streams still accumulate evidence for the full time window.
            if(candidate.count<2 || now-candidate.since<250) {
                profileCandidate=candidate
                return reject("profile_recovery_jump")
            }
            confirmedProfileTurn=true
        }

        if(yaw<=25f) {
            val nextOrder=if(points[12].x>points[11].x)1f else -1f
            if(order!=null && order!=nextOrder) { reset();return reject("order_changed") }
            val measured=base.widthScale/cos(Math.toRadians(yaw.toDouble())).toFloat()/base.heightScale
            if(!measured.isFinite() || measured<=0)return reject("invalid_front")
            if(frontCount==0) {
                order=nextOrder;frontSince=now;widthPerHeight=measured;worldRatio=ratio;frontCount=1
            } else {
                // Inconsistent front observations must not calibrate a new silhouette.
                if(measured/widthPerHeight !in .80f..1.25f) { reset();return reject("front_changed") }
                widthPerHeight+=.08f*(measured-widthPerHeight)
                worldRatio+=.08f*(ratio-worldRatio)
                if(now-frontSince>=200)frontCount++
            }
        }
        if(!ready && yaw>25f)return reject("front_required")
        lastValid=now
        lastYaw=spatial.yawDegrees
        lastImagePose=base
        // Keep the same width definition from first front acquisition through profiles.
        return bodiceFit.apply(pose.copy(widthScale=base.heightScale*widthPerHeight,unprojectedWidth=true,
            confirmedProfileTurn=confirmedProfileTurn),
            points,imageW,imageH,anchors,world)
    }
}
