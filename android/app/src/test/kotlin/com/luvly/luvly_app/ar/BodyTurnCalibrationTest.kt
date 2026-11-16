package com.luvly.luvly_app.ar

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class BodyTurnCalibrationTest {
    private val anchors=DressAnchors(1.45f,.97f,.4f,true,.53f,-.2f)
    private val frame=FrameProjection(600,900,800f,800f)
    private data class Input(val image: MutableList<BodyPoint>,val world: MutableList<WorldBodyPoint>)
    private fun input(yaw: Float=0f,depth: Float=2.5f,mirror: Boolean=false): Input {
        val source=MutableList(33){Vec3(0f,0f,0f)}
        source[11]=Vec3(-.2f,.52f,0f);source[12]=Vec3(.2f,.52f,0f)
        source[23]=Vec3(-.14f,0f,0f);source[24]=Vec3(.14f,0f,0f)
        val a=Math.toRadians(yaw.toDouble()).toFloat()
        val rotated=source.map { Vec3(it.x*cos(a)*(if(mirror)-1 else 1),it.y,-it.x*sin(a)) }
        val projection=frame.forView(600,900)!!
        return Input(rotated.map { p->
            val xy=projection.project(p+Vec3(0f,0f,-depth))!!
            BodyPoint(xy.first/600,1-xy.second/900,1f)
        }.toMutableList(),rotated.map { WorldBodyPoint(it.x,-it.y,-it.z,1f) }.toMutableList())
    }
    private fun register(t: BodyTurnCalibration,p: Input,now: Long)=
        t.register(p.image,p.world,600,900,600,900,anchors,frame,now)
    private fun calibrated(mirror: Boolean=false): BodyTurnCalibration = BodyTurnCalibration().also { t->
        for(now in listOf(1000L,1100L,1200L,1300L))assertNotNull(register(t,input(mirror=mirror),now))
        assertTrue(t.ready)
    }
    @Test fun requiresStableFrontBeforeProfileAndNeverInventsMissingWorldData() {
        val t=BodyTurnCalibration()
        assertNull(register(t,input(80f),1000))
        assertNull(register(t,input().apply { world.clear() },1100))
        assertFalse(t.ready)
        assertNotNull(register(t,input(),1200));assertFalse(t.ready)
        assertNull(register(t,input(80f),1250))
    }
    @Test fun targetReconfirmationCanResumeProfileWithoutDemandingAnotherFrontView() {
        val t=calibrated()
        assertNotNull(register(t,input(20f),1500))
        assertNotNull(register(t,input(40f),1600))
        assertNotNull(register(t,input(60f),1700))
        for(now in listOf(2000L,2300L,2600L,2900L,3200L))t.pauseForTarget(now)
        assertTrue(t.ready)
        assertNotNull(register(t,input(80f),3400))
        assertTrue(t.ready)
    }
    @Test fun pausedTargetDoesNotExtendCalibrationLifetime() {
        val t=calibrated()
        for(now in 1500L..3500L step 200)t.pauseForTarget(now)
        assertFalse(t.ready)
        assertNull(register(t,input(80f),3600))
        assertEquals("front_required",t.rejectionReason)
    }
    @Test fun slowTurnsToBothProfilesStayFiniteWithoutWidthExplosionOrShrinkage() {
        for(mirror in listOf(false,true))for(direction in listOf(-1,1)) {
            val t=calibrated(mirror);val filter=DressPoseFilter()
            val front=register(t,input(mirror=mirror),1400)!!
            filter.observe(front,1400,anchors.shoulderWidth)
            var now=1500L
            for(degrees in (0..90 step 5)+(85 downTo 0 step 5)) {
                val p=register(t,input(degrees.toFloat()*direction,mirror=mirror),now)!!
                assertTrue(p.unprojectedWidth)
                assertEquals(front.widthScale,p.widthScale,front.widthScale*.02f)
                val expected=degrees*direction*(if(mirror)-1 else 1)
                assertEquals(expected.toFloat(),p.spatial!!.yawDegrees,.02f)
                val shown=filter.observe(p,now,anchors.shoulderWidth)
                assertTrue("profile frame should not be an outlier: $degrees",shown.accepted)
                assertTrue(shown.pose!!.unprojectedWidth)
                val m=GarmentRenderTransform.matrix(shown.pose,anchors)
                assertTrue(m.all { it.isFinite() })
                assertTrue(hypot(m[0],m[2]) in front.widthScale*.95f..front.widthScale*1.05f)
                now+=100
            }
        }
    }
    @Test fun profileDistanceChangesScaleViaTorsoNotVanishingShoulderPixels() {
        val t=calibrated()
        val a=register(t,input(90f,depth=2.5f),1400)!!
        val b=register(t,input(90f,depth=2f),1500)!!
        assertEquals(1.25f,b.widthScale/a.widthScale,.03f)
        assertTrue(GarmentRenderTransform.matrix(b,anchors).all { it.isFinite() })
    }
    @Test fun lowRateProfileReturnSurvivesRegistrationFilteringAndDisplaySafety() {
        for(mirror in listOf(false,true))for(direction in listOf(-1,1))for(interval in listOf(200L,250L,280L,333L)) {
            val t=calibrated(mirror);val filter=DressPoseFilter()
            val initial=register(t,input(90f*direction,mirror=mirror),1400)!!
            filter.observe(initial,1400,anchors.shoulderWidth)
            for((index,angle) in listOf(50f,0f).withIndex()) {
                val now=1400+(index+1)*interval
                val evidence=input(angle*direction,mirror=mirror)
                val observed=register(t,evidence,now)
                assertNotNull(observed)
                var shown=filter.observe(observed,now,anchors.shoulderWidth)
                if(!shown.accepted && PoseDisplaySafety.shouldHide(shown.pose,evidence.image,
                        600,900,600,900,anchors)) {
                    filter.suppressHeldDisplay();shown=filter.displayAt(now)
                }
                assertNotNull("No blank turn frame: mirror=$mirror direction=$direction interval=$interval angle=$angle",shown.pose)
                if(index==1) {
                    assertTrue(shown.accepted)
                    assertEquals(0f,shown.pose!!.spatial!!.yawDegrees,.02f)
                }
            }
        }
    }
    @Test fun backViewCannotFlipOrderingAndLossRequiresNewFrontCalibration() {
        val t=calibrated()
        assertNull(register(t,input(120f),1400))
        assertNull(register(t,input(180f),1500))
        assertNull(register(t,input(80f),6400));assertFalse(t.ready)
        assertNotNull(register(t,input(),6500));assertFalse(t.ready)
        t.reset();assertFalse(t.ready)
    }
    @Test fun unreliableOrContradictoryProfileDoesNotExtendCalibrationLifetime() {
        val t=calibrated()
        val bad=input(80f).apply { world[11]=world[11].copy(confidence=.2f) }
        assertNull(register(t,bad,1400))
        assertNull(register(t,input(80f).apply { image[12]=image[12].copy(x=.9f) },1500))
        assertNull(register(t,bad,4000));assertTrue(t.ready)
        assertNull(register(t,input(80f),6400));assertFalse(t.ready)
    }
    @Test fun narrowShouldersWithVisibleTorsoDoNotTellUserToMoveCloser() {
        val side=input(90f)
        assertEquals(PoseGuidance.Issue.TURN,PoseGuidance.assess(side.image,600,900,600,900))
        assertNotEquals(PoseGuidance.Issue.TOO_FAR,PoseGuidance.assess(input(75f).image,600,900,600,900))
    }
    @Test fun calibratedShoulderPivotRemainsFixedAtNinetyDegrees() {
        val t=calibrated();val p=register(t,input(90f),1400)!!
        val m=GarmentRenderTransform.matrix(p,anchors)
        assertEquals(p.x,m[4]*anchors.shoulderY+m[8]*anchors.bodyZ+m[12],.001f)
        assertEquals(p.y,m[5]*anchors.shoulderY+m[9]*anchors.bodyZ+m[13],.001f)
    }

    @Test fun calibratedProfilesAllowPartlyOccludedHipsWithoutInventingJoints() {
        for(mirror in listOf(false,true))for(direction in listOf(-1,1)) {
            val t=calibrated(mirror)
            val p=input(80f*direction,mirror=mirror).apply {
                image[23]=image[23].copy(confidence=.5f)
                image[24]=image[24].copy(confidence=.7f)
                world[23]=world[23].copy(confidence=.5f)
                world[24]=world[24].copy(confidence=.7f)
            }
            assertNotNull(register(t,p,1400))
            assertEquals("none",t.rejectionReason)
            p.image[23]=p.image[23].copy(confidence=.2f)
            assertNull(register(t,p,1500))
            assertEquals("image_confidence",t.rejectionReason)
        }
    }

    @Test fun partialConfidenceDoesNotRelaxFrontAcquisitionOrInvalidWorldGeometry() {
        val t=calibrated()
        assertNull(register(t,input().apply { image[23]=image[23].copy(confidence=.5f) },1400))
        assertEquals("image_confidence",t.rejectionReason)
        assertNull(register(t,input(80f).apply { world[11]=world[11].copy(x=Float.NaN) },1500))
        assertEquals("invalid_world",t.rejectionReason)
        assertNull(register(t,input(80f).apply { image[23]=image[23].copy(y=1.2f) },1600))
        assertEquals("out_of_frame",t.rejectionReason)
    }

    @Test fun gradualProfileToleratesSmallAngleNoiseButNotBackViewsOrSuddenFlips() {
        for(direction in listOf(-1,1))for(mirror in listOf(false,true)) {
            val t=calibrated(mirror)
            var now=1400L
            for(angle in listOf(40f,60f,80f,90f,96f,94f,89f,80f,60f,30f,0f)) {
                val p=register(t,input(angle*direction,mirror=mirror),now)
                assertNotNull("gradual turn $angle mirrored=$mirror",p)
                assertTrue(GarmentRenderTransform.matrix(p!!,anchors).all { it.isFinite() })
                now+=100
            }
            assertNull(register(t,input(96f*direction,mirror=mirror),now))
            assertEquals("turn_limit",t.rejectionReason)
            assertNotNull(register(t,input(80f*direction,mirror=mirror),now+100))
            assertNull(register(t,input(115f*direction,mirror=mirror),now+200))
            assertNull(register(t,input(180f,mirror=mirror),now+300))
        }
    }

    @Test fun tolerantProfileCannotStartAfterLongLossOrJumpAcrossSides() {
        val t=calibrated()
        assertNotNull(register(t,input(80f),1400))
        assertNull(register(t,input(-96f),1500));assertEquals("turn_jump",t.rejectionReason)
        assertNotNull(register(t,input(96f),1900)) // Visible continuous body can recover past 350 ms.
        assertNull(register(t,input(96f),7000));assertFalse(t.ready)
    }

    @Test fun visibleBodyRetainsCalibrationButDoesNotKeepOldDressVisible() {
        val t=calibrated();val filter=DressPoseFilter()
        val p=register(t,input(80f),1400)!!
        filter.observe(p,1400,anchors.shoulderWidth)
        val noWorld=input(80f).apply { world.clear() }
        assertNull(register(t,noWorld,3100));assertTrue(t.ready)
        assertNull(filter.observe(null,3100,anchors.shoulderWidth).pose)
        assertNotNull(register(t,input(90f),3300))
    }

    @Test fun imageAnchoredRecoveryWorksDuringGradualTurnsButRejectsSuddenSideFlips() {
        val t=BodyTurnCalibration()
        fun observation(yaw: Float,now: Long): DressPose? {
            val d=input(yaw)
            for(i in d.image.indices) {
                val p=d.world[i].cameraVector()
                d.image[i]=BodyPoint((300+p.x*400)/600,1-(450+p.y*400)/900,1f)
            }
            return t.register(d.image,d.world,600,900,600,900,anchors,FrameProjection(600,900,250f,250f),now)
        }
        for(now in listOf(1000L,1100L,1200L,1300L))assertNotNull(observation(0f,now))
        assertTrue(t.ready)
        assertNotNull(observation(20f,1400));assertNotNull(observation(40f,1500))
        assertNotNull(observation(60f,1600))
        assertEquals("image-anchored-profile",observation(80f,1800)!!.spatial!!.registrationMode)
        assertNull(observation(-80f,2000));assertEquals("profile_recovery_jump",t.rejectionReason)
        assertNotNull(observation(85f,3500))
    }

    @Test fun unseenOrMovedBodyRequiresNewFrontAfterShortLoss() {
        val unseen=calibrated()
        assertNull(register(unseen,input().apply { image.clear();world.clear() },3000))
        assertFalse(unseen.ready)
        val moved=calibrated()
        val p=input(80f).apply { for(i in image.indices)image[i]=image[i].copy(x=image[i].x+.25f) }
        assertNull(register(moved,p,3000));assertFalse(moved.ready)
    }

    private fun weakObservation(t: BodyTurnCalibration,yaw: Float,now: Long,missing: Boolean=false): DressPose? {
        val d=input(yaw)
        for(i in d.image.indices) {
            val p=d.world[i].cameraVector()
            d.image[i]=BodyPoint((300+p.x*400)/600,1-(450+p.y*400)/900,1f)
        }
        if(missing)d.world.clear()
        return t.register(d.image,d.world,600,900,600,900,anchors,FrameProjection(600,900,250f,250f),now)
    }
    private fun weakCalibrated(): BodyTurnCalibration = BodyTurnCalibration().also { t->
        for(now in listOf(1000L,1100L,1200L,1300L))assertNotNull(weakObservation(t,0f,now))
    }
    @Test fun sustainedValidProfileRecoversWithoutReturningToOldAngle() {
        for(sign in listOf(-1f,1f)) {
            val t=weakCalibrated()
            assertNotNull(weakObservation(t,27f*sign,1500))
            assertNull(weakObservation(t,70f*sign,1700))
            assertEquals("profile_recovery_jump",t.rejectionReason)
            assertNull(weakObservation(t,80f*sign,1900))
            val recovered=weakObservation(t,88f*sign,2100)
            assertNotNull("Three independently fitted, coherent profile observations should recover",recovered)
            assertEquals("image-anchored-profile",recovered!!.spatial!!.registrationMode)
        }
    }
    @Test fun validatedProfileRecoveryReachesDisplayWithoutDoubleConfirmation() {
        for(sign in listOf(-1f,1f)) {
            val t=weakCalibrated();val f=DressPoseFilter()
            f.observe(weakObservation(t,20f*sign,1500),1500,anchors.shoulderWidth)
            assertFalse(f.observe(weakObservation(t,65f*sign,1780),1780,anchors.shoulderWidth).accepted)
            val verified=weakObservation(t,80f*sign,2060)!!
            assertTrue(verified.confirmedProfileTurn)
            assertTrue(f.observe(verified,2060,anchors.shoulderWidth).accepted)
            assertFalse(weakObservation(t,85f*sign,2620)!!.confirmedProfileTurn)
        }
    }
    @Test fun profileRecoveryAccumulatesEvidenceAtFastAndVariableFrameRates() {
        val schedules=listOf(
            listOf(0L,33L,66L,99L,132L,165L,198L,231L,264L),
            listOf(0L,66L,132L,198L,264L),
            listOf(0L,40L,106L,206L,286L),
            listOf(0L,100L,200L,300L),
            listOf(0L,280L))
        for(sign in listOf(-1f,1f))for(schedule in schedules) {
            val t=weakCalibrated()
            assertNotNull(weakObservation(t,20f*sign,1500))
            for(offset in schedule) {
                val pose=weakObservation(t,80f*sign,1700+offset)
                if(offset<250)assertNull("Must collect 250 ms of evidence",pose)
                else {
                    assertNotNull("Profile recovery starved at $schedule",pose)
                    assertTrue(pose!!.confirmedProfileTurn)
                }
            }
        }
    }
    @Test fun repeatedTimestampsCannotConfirmProfileRecovery() {
        val t=weakCalibrated()
        assertNotNull(weakObservation(t,20f,1500))
        repeat(12) { assertNull(weakObservation(t,80f,1700)) }
        assertNull(weakObservation(t,80f,1800))
        assertNotNull(weakObservation(t,80f,2000))
    }
    @Test fun profileRecoveryCannotBridgeMissingDataLongGapsOrOppositeSides() {
        val missing=weakCalibrated()
        assertNotNull(weakObservation(missing,27f,1500))
        assertNull(weakObservation(missing,70f,1700))
        assertNull(weakObservation(missing,80f,1800,missing=true))
        assertNull(weakObservation(missing,80f,1900))
        assertNull(weakObservation(missing,88f,2100))
        assertNotNull(weakObservation(missing,88f,2300))
        val gap=weakCalibrated()
        assertNotNull(weakObservation(gap,27f,1500))
        assertNull(weakObservation(gap,70f,1700))
        assertNull(weakObservation(gap,80f,2200))
        assertNull(weakObservation(gap,88f,2400))
        val flip=weakCalibrated()
        assertNotNull(weakObservation(flip,20f,1350))
        assertNotNull(weakObservation(flip,40f,1400))
        assertNotNull(weakObservation(flip,60f,1500))
        for(time in listOf(1700L,1900L,2100L,2300L))assertNull(weakObservation(flip,-80f,time))
        assertNull(weakObservation(flip,120f,2500))
    }
    @Test fun profileCandidatesDoNotSurviveResetOrExtendCalibrationLifetime() {
        val t=weakCalibrated()
        assertNotNull(weakObservation(t,27f,1500))
        assertNull(weakObservation(t,70f,1700))
        t.reset()
        assertNull(weakObservation(t,80f,1900));assertFalse(t.ready)
        val stale=weakCalibrated()
        assertNotNull(weakObservation(stale,20f,1600))
        assertNotNull(weakObservation(stale,40f,1700))
        assertNotNull(weakObservation(stale,60f,1800))
        for(now in 2000L..6600L step 200)assertNull(weakObservation(stale,-80f,now))
        assertNull(weakObservation(stale,-80f,7000));assertFalse(stale.ready)
    }
}
