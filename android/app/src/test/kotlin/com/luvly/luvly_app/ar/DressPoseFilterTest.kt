package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

class DressPoseFilterTest {
    private val base=DressPose(300f,400f,500f,500f,0f)
    private fun turned(degrees: Float,x: Float=base.x): DressPose {
        val a=Math.toRadians(degrees.toDouble()).toFloat()
        return base.copy(x=x,unprojectedWidth=true,spatial=SpatialDressPose(
            Vec3(0f,.5f,-2.5f),Vec3(cos(a),0f,-sin(a)),Vec3(0f,1f,0f),1f,1f,
            PerspectiveProjection(600,900,800f,800f,300f,450f,"test"),0f))
    }
    @Test fun continuousLowRateTurnDoesNotRestartConfirmationAtEveryLargeStep() {
        for(sign in listOf(-1f,1f)) {
            val f=DressPoseFilter();f.observe(turned(90f*sign),1000,.4f)
            assertFalse(f.observe(turned(50f*sign),1250,.4f).accepted)
            val recovered=f.observe(turned(0f),1500,.4f)
            assertTrue("A continuous 90 -> 50 -> 0 turn must confirm its second observation",recovered.accepted)
            assertEquals(0f,recovered.pose!!.spatial!!.yawDegrees,.01f)
        }
    }
    @Test fun continuousTurnWithSmallAccumulatedTranslationConfirmsCurrentPose() {
        // Ratios/timing from the 2090 trace; synthetic positions, not raw joint replay.
        for(sign in listOf(-1f,1f)) {
            val f=DressPoseFilter();f.observe(turned(97.35f*sign),1000,.4f)
            val first=turned(65.31f*sign,x=331.94f).copy(widthScale=479.75f,heightScale=479.75f)
            val second=turned(14.37f*sign,x=363.36f).copy(widthScale=428.65f,heightScale=432.2f)
            assertFalse(f.observe(first,1242,.4f).accepted)
            val shown=f.observe(second,1436,.4f)
            assertTrue(shown.accepted)
            assertEquals(second,shown.pose)
        }
    }
    @Test fun trackedTurnWithModerateFirstShiftConfirmsSecondCoherentObservation() {
        // 2128 phone trace, 86.211–86.448 s and 89.547–89.732 s.
        // Reconstruct only normalized motion, not a person's joint coordinates.
        val samples=listOf(floatArrayOf(72f,12.6865f,8.4685f,.2444f,.3069f,.9338f,.9371f),
            floatArrayOf(-25f,-69.487f,-82.0499f,.3110f,.3922f,1.0161f,1.0526f))
        for(s in samples) for(sign in listOf(-1f,1f)) {
            val f=DressPoseFilter();f.observe(turned(s[0]*sign),1000,.4f)
            val first=turned(s[1]*sign,300f+200f*s[3]).copy(widthScale=500f*s[5],heightScale=500f*s[5])
            val next=turned(s[2]*sign,300f+200f*s[4]).copy(widthScale=500f*s[6],heightScale=500f*s[6])
            assertFalse(f.observe(first,1268,.4f).accepted)
            f.suppressHeldDisplay()
            assertTrue("Bounded continuous turn must resume on its second current observation",f.observe(next,1505,.4f).accepted)
            assertEquals("confirmed_turn",f.decisionReason)
        }
    }
    @Test fun moderateShiftDoesNotFastConfirmReversalOrStationaryRelocation() {
        for(x in listOf(340f,362f,400f)) {
            val f=DressPoseFilter();f.observe(turned(0f),1000,.4f)
            assertFalse(f.observe(turned(65f,362f),1250,.4f).accepted)
            assertFalse(f.observe(turned(80f,x),1500,.4f).accepted)
        }
    }
    @Test fun accumulatedTranslationRejectsReversalsLargeStepsAndScaleJumps() {
        for(next in listOf(turned(14f,x=260f),turned(14f,x=400f),
                turned(14f,x=363f).copy(heightScale=650f))) {
            val f=DressPoseFilter();f.observe(turned(97f),1000,.4f)
            assertFalse(f.observe(turned(65f,x=332f),1242,.4f).accepted)
            assertFalse(f.observe(next,1436,.4f).accepted)
        }
    }
    @Test fun confirmedContinuousTurnCanRecoverSuppressedDisplayButNotCaptureImmediately() {
        val f=DressPoseFilter();val ready=PreviewReadiness()
        f.observe(turned(90f),1000,.4f)
        ready.observe(f.observe(turned(50f),1250,.4f).accepted,1250)
        f.suppressHeldDisplay()
        assertNull(f.displayAt(1250).pose)
        val recovered=f.observe(turned(0f),1500,.4f)
        ready.observe(recovered.accepted,1500)
        assertNotNull(recovered.pose)
        assertTrue(recovered.accepted)
        assertFalse(ready.ready(1500))
    }
    @Test fun reversingOrExcessivelyFastCandidatesDoNotFastConfirm() {
        for(pair in listOf(0f to 35f,50f to -20f)) {
            val f=DressPoseFilter();f.observe(turned(90f),1000,.4f)
            assertFalse(f.observe(turned(pair.first),1250,.4f).accepted)
            assertFalse(f.observe(turned(pair.second),1500,.4f).accepted)
        }
    }
    @Test fun aMissingObservationBreaksTurnEvidence() {
        val f=DressPoseFilter();f.observe(turned(90f),1000,.4f)
        assertFalse(f.observe(turned(50f),1250,.4f).accepted)
        assertFalse(f.observe(null,1300,.4f).accepted)
        assertFalse(f.observe(turned(0f),1500,.4f).accepted)
    }
    @Test fun changingPositionOrSizeDuringTurnCannotUseFastRoute() {
        for(next in listOf(turned(0f,x=350f),turned(0f).copy(heightScale=650f))) {
            val f=DressPoseFilter();f.observe(turned(90f),1000,.4f)
            assertFalse(f.observe(turned(50f),1250,.4f).accepted)
            assertFalse(f.observe(next,1500,.4f).accepted)
        }
    }
    @Test fun lowRateRotationCanConfirmInTwoObservationsWithoutAcceptingOneSpike() {
        val f=DressPoseFilter();val start=turned(90f);f.observe(start,1000,.4f)
        assertFalse(f.observe(turned(45f),1250,.4f).accepted)
        val recovered=f.observe(turned(30f),1500,.4f)
        assertTrue(recovered.accepted);assertEquals(30f,recovered.pose!!.spatial!!.yawDegrees,.01f)
        val spike=DressPoseFilter();spike.observe(start,1000,.4f)
        assertFalse(spike.observe(turned(0f),1250,.4f).accepted)
        assertTrue(spike.observe(start,1500,.4f).accepted)
        assertEquals(90f,spike.displayAt(1500).pose!!.spatial!!.yawDegrees,.01f)
    }
    @Test fun oppositeSideFlipsAndRelocationsStillNeedThreeObservations() {
        for(next in listOf(turned(-80f),turned(0f,x=380f),turned(0f).copy(widthScale=650f))) {
            val f=DressPoseFilter();f.observe(turned(80f),1000,.4f)
            assertFalse(f.observe(next,1250,.4f).accepted)
            assertFalse(f.observe(next,1500,.4f).accepted)
            assertTrue(f.observe(next,1750,.4f).accepted)
        }
    }
    @Test fun widelySeparatedRotationObservationsDoNotUseFastConfirmation() {
        val f=DressPoseFilter();f.observe(turned(80f),1000,.4f)
        assertFalse(f.observe(turned(0f),1100,.4f).accepted)
        assertFalse(f.observe(turned(0f),1600,.4f).accepted)
    }
    @Test fun startsAtObservedBodyAndReducesStationaryJitter() {
        val f=DressPoseFilter()
        assertEquals(base,f.observe(base,1000,.4f).pose)
        val next=f.observe(base.copy(x=302f),1100,.4f)
        assertTrue(next.accepted)
        assertTrue(next.pose!!.x in 300f..301.5f)
    }
    @Test fun independentlyConfirmedProfileDoesNotWaitForAnotherConfirmationWindow() {
        for(sign in listOf(-1f,1f)) {
            val f=DressPoseFilter();f.observe(turned(20f*sign),1000,.4f)
            f.observe(null,1250,.4f);f.observe(null,1500,.4f);f.suppressHeldDisplay()
            val p=turned(80f*sign).copy(confirmedProfileTurn=true)
            val result=f.observe(p,1750,.4f)
            assertTrue(result.accepted);assertNotNull(result.pose)
            assertEquals("registered_profile_turn",f.decisionReason)
            assertFalse(result.pose!!.confirmedProfileTurn)
        }
    }
    @Test fun profileProofDoesNotAuthorizeRelocationOrScaleJumpOrSideFlip() {
        for(p in listOf(turned(80f,600f),turned(80f).copy(heightScale=700f),turned(-90f))) {
            val f=DressPoseFilter();f.observe(turned(25f),1000,.4f)
            assertFalse(f.observe(p.copy(confirmedProfileTurn=true),1250,.4f).accepted)
        }
    }
    @Test fun respondsToMovementFasterThanFixedOldSmoothing() {
        val f=DressPoseFilter();f.observe(base,1000,.4f)
        val next=f.observe(base.copy(x=360f),1100,.4f).pose!!
        assertTrue(next.x>321f) // Old 0.35 filter left 39 pixels of lag.
        assertTrue(next.x<360f)
    }
    @Test fun oneOutlierDoesNotDragDressAcrossScreen() {
        val f=DressPoseFilter();f.observe(base,1000,.4f)
        val outlier=f.observe(base.copy(x=800f),1100,.4f)
        assertFalse(outlier.accepted);assertEquals(base,outlier.pose)
        assertTrue(f.observe(base,1200,.4f).accepted)
        assertEquals(base,f.observe(base,1300,.4f).pose)
    }
    @Test fun consistentNewPositionCanBeReacquired() {
        val f=DressPoseFilter();f.observe(base,1000,.4f)
        val next=base.copy(x=650f)
        assertFalse(f.observe(next,1100,.4f).accepted)
        assertFalse(f.observe(next,1200,.4f).accepted)
        assertEquals(FilteredDressPose(next,true),f.observe(next,1300,.4f))
    }
    @Test fun briefDropoutIsDisplayOnlyAndLongLossClearsPose() {
        val f=DressPoseFilter();f.observe(base,1000,.4f)
        assertEquals(FilteredDressPose(base,false),f.observe(null,1200,.4f))
        assertEquals(FilteredDressPose(base,false),f.observe(null,1500,.4f))
        assertEquals(FilteredDressPose(null,false),f.observe(null,2000,.4f))
        val next=base.copy(x=900f)
        assertEquals(FilteredDressPose(next,true),f.observe(next,2100,.4f))
    }

    @Test fun graceHasBoundedFadeEvenWhenCameraStopsDeliveringFrames() {
        val f=DressPoseFilter();f.observe(base,1000,.4f)
        assertEquals(1f,f.displayAt(1650).opacity,0f)
        assertEquals(.5f,f.displayAt(1825).opacity,.001f)
        assertEquals(FilteredDressPose(null,false),f.displayAt(2000))
        assertEquals(FilteredDressPose(null,false),f.displayAt(10000))
    }

    @Test fun missingFramesCannotExtendGraceIndefinitely() {
        val f=DressPoseFilter();f.observe(base,1000,.4f)
        for(time in 1100L..1900L step 100) assertFalse(f.observe(null,time,.4f).accepted)
        assertNull(f.observe(null,2000,.4f).pose)
        assertNull(f.observe(null,2100,.4f).pose)
    }

    @Test fun halfSecondConfidenceDropoutDoesNotBlinkOrAuthorizeCapture() {
        val f=DressPoseFilter();val ready=PreviewReadiness()
        for(time in 1000L..1800L step 100)ready.observe(f.observe(base,time,.4f).accepted,time)
        assertTrue(ready.ready(1800))
        for(time in 1900L..2300L step 100) {
            val shown=f.observe(null,time,.4f)
            ready.observe(shown.accepted,time)
            assertEquals(base,shown.pose);assertEquals(1f,shown.opacity,0f)
            assertFalse(ready.ready(time))
        }
        ready.observe(f.observe(base,2400,.4f).accepted,2400)
        assertFalse(ready.ready(2400))
        ready.observe(f.observe(base,3000,.4f).accepted,3000)
        assertTrue(ready.ready(3000))
    }

    @Test fun delayedDetectorResultDoesNotSpendDisplayGraceBeforeItArrives() {
        val f=DressPoseFilter();val ready=PreviewReadiness()
        // Captured at 1000, arrived at 1450 after 450 ms of processing.
        val shown=f.observe(base,1450,.4f)
        ready.observe(shown.accepted,1000)
        assertEquals(1f,f.displayAt(1900).opacity,0f)
        assertFalse(ready.ready(1900)) // Independent stale input, not a photo opportunity.
        assertNull(f.displayAt(2450).pose)
    }

    @Test fun resetOrBackwardsClockNeverLeavesAnOldDressVisible() {
        val f=DressPoseFilter();f.observe(base,1000,.4f)
        assertNull(f.displayAt(999).pose)
        f.reset();assertNull(f.displayAt(1100).pose)
    }
    @Test fun resetRemovesPriorCameraCoordinates() {
        val f=DressPoseFilter();f.observe(base,1000,.4f);f.reset()
        val next=base.copy(x=50f,y=900f)
        assertEquals(next,f.observe(next,1100,.4f).pose)
    }
    @Test fun smoothingIsTimeBasedAcrossDifferentFrameRates() {
        fun sample(step: Long): Float {
            val f=DressPoseFilter();f.observe(base,1000,.4f)
            var x=base.x
            var time=1000+step
            while(time<=2000) {
                x=f.observe(base.copy(x=310f),time,.4f).pose!!.x
                time+=step
            }
            return x
        }
        assertTrue(abs(sample(50)-sample(100))<1f)
    }
}
