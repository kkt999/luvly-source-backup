package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class BodyTargetLockTest {
    private fun body(x: Float=.55f,y: Float=.55f,scale: Float=1f,side: Boolean=false,confidence: Float=1f): List<BodyPoint> {
        val p=MutableList(33){BodyPoint(x,y,confidence)}
        val w=if(side).01f else .11f*scale
        p[11]=BodyPoint(x-w,y-.15f*scale,confidence);p[12]=BodyPoint(x+w,y-.15f*scale,confidence)
        p[23]=BodyPoint(x-.07f*scale,y+.15f*scale,confidence);p[24]=BodyPoint(x+.07f*scale,y+.15f*scale,confidence)
        return p
    }
    private fun select(t: BodyTargetLock,now: Long,vararg bodies: List<BodyPoint>)=t.select(bodies.toList(),600,900,now)
    private fun acquired(): BodyTargetLock=BodyTargetLock().also { t->
        assertNull(select(t,1000,body(.12f),body()).index)
        assertNull(select(t,1200,body(.12f),body()).index)
        val result=select(t,1400,body(.12f),body())
        assertEquals(1,result.index);assertTrue(result.resetAlignment)
    }
    @Test fun confirmsCentralFrontRatherThanFirstDetectorResult() { acquired() }
    @Test fun fastFramesCanAcquireAndReconfirmWithoutShorteningObservationWindow() {
        for(interval in listOf(33L,66L,100L))for(reacquire in listOf(false,true)) {
            val t=if(reacquire)acquired() else BodyTargetLock()
            val start=if(reacquire)2400L else 1000L
            var result=select(t,start,body())
            assertNull(result.index)
            var elapsed=interval
            while(elapsed<250) {
                result=select(t,start+elapsed,body())
                assertNull("Confirmation must span 250 ms",result.index)
                elapsed+=interval
            }
            result=select(t,start+elapsed,body())
            assertEquals("Recovery must not starve at $interval ms",0,result.index)
            assertEquals(if(reacquire)"target_reacquired" else "target_acquired",result.reason)
        }
    }
    @Test fun detectionOrderCanChangeWithoutChangingTarget() {
        val t=acquired()
        assertEquals(0,select(t,1600,body(),body(.12f)).index)
        assertEquals(1,select(t,1800,body(.12f),body(side=true)).index)
    }
    @Test fun lossNeverAutomaticallyTransfersToReflectionEvenAfterLongWait() {
        val t=acquired()
        for(time in 1600L..12000L step 200) {
            val r=select(t,time,body(.12f))
            assertNull(r.index);assertEquals("target_lost",r.reason)
        }
    }
    @Test fun returnAtSameLocationReconfirmsAndResetsAlignment() {
        val t=acquired();assertNull(select(t,3000,body(.12f)).index)
        assertNull(select(t,3200,body()).index)
        assertNull(select(t,3400,body()).index)
        val r=select(t,3600,body())
        assertEquals(0,r.index);assertEquals("target_reacquired",r.reason);assertTrue(r.resetAlignment)
    }
    @Test fun loneFrontViewAtNewDistanceGetsFreshAlignmentAfterLoss() {
        val t=acquired()
        val moved=body(.48f,scale=1.6f)
        assertEquals("target_lost",select(t,1800,moved).reason)
        assertEquals("target_reconfirming",select(t,2900,moved).reason)
        assertNull(select(t,3650,moved).index)
        val result=select(t,4400,moved)
        assertEquals(0,result.index)
        assertEquals("target_reacquired",result.reason)
        assertTrue(result.resetAlignment)
        assertFalse(result.retainCalibration)
    }
    @Test fun relocationCannotAccumulateAcrossAnAmbiguousFrame() {
        val t=acquired()
        val moved=body(.46f,scale=1.7f)
        assertNull(select(t,2900,moved).index)
        assertNull(select(t,3200,moved,body(.12f)).index)
        assertNull(select(t,3500,moved).index)
        assertNull(select(t,3800,moved).index)
        assertEquals("target_reacquired",select(t,4100,moved).reason)
    }
    @Test fun briefOcclusionDoesNotRequireNewTargetOrChooseOtherBody() {
        val t=acquired()
        assertNull(select(t,1600,body(confidence=.1f),body(.12f)).index)
        val r=select(t,1800,body(side=true),body(.12f))
        assertEquals(0,r.index);assertFalse(r.resetAlignment)
    }
    @Test fun confirmedBriefProfileReturnRetainsCalibrationButResetsDisplay() {
        val t=acquired()
        assertNull(select(t,1600,body(confidence=.1f)).index)
        assertNull(select(t,2200,body(side=true)).index)
        assertNull(select(t,2400,body(side=true)).index)
        val r=select(t,2600,body(side=true))
        assertEquals("target_reacquired",r.reason)
        assertTrue(r.resetAlignment);assertTrue(r.retainCalibration)
    }
    @Test fun longLossAmbiguityMovementAndScaleChangesCannotReuseCalibration() {
        for(kind in listOf("long","ambiguous","moved","scaled")) {
            val t=acquired()
            if(kind=="ambiguous")select(t,1600,body(.53f),body(.57f))
            else select(t,1600,body(confidence=.1f))
            val p=when(kind) {
                "moved" -> body(.65f)
                "scaled" -> body(scale=1.2f)
                else -> body(side=true)
            }
            val start=if(kind=="long")3000L else 2200L
            assertNull(select(t,start,p).index);assertNull(select(t,start+200,p).index)
            val r=select(t,start+400,p)
            assertNotNull(kind,r.index);assertTrue(r.resetAlignment);assertFalse(kind,r.retainCalibration)
        }
    }
    @Test fun gradualMovementAndDistanceChangesFollowSelectedBody() {
        val t=acquired()
        for(i in 1..8)assertEquals(0,select(t,1400+i*200L,body(.55f+i*.02f,scale=1f+i*.02f),body(.12f)).index)
    }
    @Test fun slowFramesStillTrackTheSameBodyWithoutRestartingAlignment() {
        val t=acquired()
        val result=select(t,2220,body())
        assertEquals("target_tracked",result.reason)
        assertFalse(result.resetAlignment)
    }
    @Test fun abruptMovementRequiresExplicitResetNotSilentTransfer() {
        val t=acquired()
        for(i in 1..6)assertNull(select(t,1400+i*200L,body(.15f)).index)
        t.reset()
        assertNull(select(t,3000,body(.45f)).index)
        assertNull(select(t,3200,body(.45f)).index)
        assertEquals(0,select(t,3400,body(.45f)).index)
    }
    @Test fun overlappingCandidatesPauseRatherThanGuess() {
        val t=acquired()
        assertEquals("target_ambiguous",select(t,1600,body(.53f),body(.57f)).reason)
        assertNull(select(t,1800,body(.53f),body(.57f)).index)
    }
    @Test fun duplicateCropsOfAnActiveSideProfileDoNotBreakTracking() {
        val t=acquired()
        val profile=body(side=true)
        val duplicate=body(.56f,side=true,scale=1.02f)
        assertEquals(0,select(t,1600,profile).index)
        assertEquals(1,select(t,1800,duplicate,profile).index)
        assertEquals(0,select(t,2000,profile,duplicate).index)
    }
    @Test fun duplicateCropsCanConfirmOnePersonAtStartupAndAfterMoving() {
        val front=body()
        val duplicate=body(.56f)
        val newLock=BodyTargetLock()
        assertEquals("target_confirming",select(newLock,1000,front,duplicate).reason)
        assertNull(select(newLock,1200,duplicate,front).index)
        assertEquals("target_acquired",select(newLock,1400,front).reason)
        val closer=body(.51f,scale=1.55f)
        val secondCrop=body(.52f,scale=1.55f)
        val lock=acquired()
        assertEquals("target_lost",select(lock,2000,closer,secondCrop).reason)
        assertEquals("target_reconfirming",select(lock,3000,closer,secondCrop).reason)
        assertNull(select(lock,3200,closer).index)
        val recovered=select(lock,3400,secondCrop,closer)
        assertEquals("target_reacquired",recovered.reason)
        assertFalse(recovered.retainCalibration)
    }
    @Test fun uncertainOrDistinctFacesInOverlappingCropsStillPause() {
        val front=body()
        val duplicate=body(.56f)
        val unreliable=duplicate.toMutableList().apply { this[0]=this[0].copy(confidence=.1f) }
        assertEquals("target_ambiguous",select(acquired(),1600,front,unreliable).reason)
        assertEquals("target_ambiguous",select(BodyTargetLock(),1000,front,unreliable).reason)
        val otherFace=duplicate.toMutableList().apply { this[2]=this[2].copy(x=.62f) }
        assertEquals("target_ambiguous",select(acquired(),1600,front,otherFace).reason)
    }
    @Test fun equallyCentralPeopleAndSidewaysStartsDoNotAcquire() {
        val pair=BodyTargetLock();val side=BodyTargetLock()
        for(time in listOf(1000L,1200L,1400L)) {
            assertNull(select(pair,time,body(.45f),body(.55f)).index)
            assertNull(select(side,time,body(side=true)).index)
        }
    }
    @Test fun missingAndStaleFramesBreakConfirmationWithoutUnlocking() {
        val t=BodyTargetLock()
        assertNull(select(t,1000,body()).index)
        assertNull(select(t,1200,body()).index)
        assertNull(select(t,1200,body()).index)
        assertNull(select(t,1400,body()).index)
        assertNull(select(t,1600).index)
        assertNull(select(t,1800,body()).index)
        assertNull(select(t,2000,body()).index)
        assertEquals(0,select(t,2200,body()).index)
        assertNull(select(t,2100,body(.12f)).index)
        assertNull(select(t,2400,body(.12f)).index)
    }
    @Test fun invalidClippedOrScaleJumpCannotAcquireOrStealTarget() {
        val t=acquired()
        val invalid=body().toMutableList().apply { this[11]=this[11].copy(x=Float.NaN) }
        for((i,p) in listOf(invalid,body(y=.99f),body(scale=2f),body(confidence=.2f)).withIndex())
            assertNull(select(t,1600+i*200L,p).index)
        assertNull(t.select(listOf(body()),0,900,2600).index)
    }
}
