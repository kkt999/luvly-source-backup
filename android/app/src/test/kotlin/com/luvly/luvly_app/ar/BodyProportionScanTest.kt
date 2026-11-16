package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test

class BodyProportionScanTest {
    private fun joints()=MutableList(33){BodyProportionScan.Joint(.5,.5,0.0,1.0)}.apply{
        this[0]=this[0].copy(y=.16)
        this[11]=this[11].copy(x=.30,y=.33);this[12]=this[12].copy(x=.70,y=.33)
        this[23]=this[23].copy(x=.36,y=.57);this[24]=this[24].copy(x=.64,y=.57)
        this[25]=this[25].copy(x=.36,y=.75);this[26]=this[26].copy(x=.64,y=.75)
    }
    private fun world()=MutableList(33){BodyProportionScan.Joint(0.0,0.0,0.0,1.0)}.apply{
        this[0]=this[0].copy(y=-.5,z=-.15)
        this[11]=this[11].copy(x=-.2,y=-.3);this[12]=this[12].copy(x=.2,y=-.3)
        this[23]=this[23].copy(x=-.14,y=.2);this[24]=this[24].copy(x=.14,y=.2)
    }
    private fun feed(s: BodyProportionScan,p: List<BodyProportionScan.Joint> = joints(),w: List<BodyProportionScan.Joint> = world(),time: Long=1000,bright: Double=120.0)=s.add(listOf(p),listOf(w),400,800,time,bright)
    private fun complete(s: BodyProportionScan=BodyProportionScan(),p: List<BodyProportionScan.Joint> = joints(),w: List<BodyProportionScan.Joint> = world()): BodyProportionScan.Result {
        var update=BodyProportionScan.Update("")
        for(i in 0..14)update=feed(s,p,w,1000+i*250L)
        return requireNotNull(update.result)
    }
    @Test fun requiresRecentContinuousSamplesAndTimeNotOneOldFrame(){
        val s=BodyProportionScan();assertNull(feed(s).result)
        assertEquals(1,feed(s,time=5000).count)
        s.reset();for(i in 0..13)assertNull(feed(s,time=1000+i*250L).result)
        assertNotNull(feed(s,time=4500).result)
        val fast=BodyProportionScan();for(i in 0..29)assertNull(feed(fast,time=1000+i*10L).result)
    }
    @Test fun givesAspectCorrectedRatiosAndRepeatabilityNotCentimetres(){
        val r=complete();assertEquals(160.0/112,r.shoulderHipRatio,.00001)
        assertEquals(192.0/160,r.torsoShoulderRatio,.00001)
        assertEquals(15,r.sampleCount);assertEquals(3500L,r.durationMs);assertEquals(0.0,r.relativeSpread,0.0)
    }
    @Test fun invariantToMirroringAndUniformImageScaling(){
        val base=complete()
        val mirror=complete(p=joints().map{it.copy(x=1-it.x)},w=world().map{it.copy(x=-it.x)})
        val smaller=complete(p=joints().map{it.copy(x=.5+(it.x-.5)*.8,y=.5+(it.y-.5)*.8)})
        for(r in listOf(mirror,smaller)){
            assertEquals(base.shoulderHipRatio,r.shoulderHipRatio,.00001)
            assertEquals(base.torsoShoulderRatio,r.torsoShoulderRatio,.00001)
        }
    }
    @Test fun rejectsSideBackLeanAndLowVisibility(){
        for((p,w)in listOf(
            joints() to world().apply{this[11]=this[11].copy(z=.2)},
            joints() to world().apply{this[0]=this[0].copy(z=.2)},
            joints().apply{this[23]=this[23].copy(x=.55);this[24]=this[24].copy(x=.83)} to world(),
            joints().apply{this[11]=this[11].copy(confidence=.3)} to world(),
            joints().apply{this[24]=this[24].copy(x=.99)} to world(),
            joints().apply{this[11]=this[11].copy(x=Double.NaN)} to world(),
            joints().apply{this[24]=this[24].copy(z=Double.NaN)} to world()
        ))assertEquals(0,feed(BodyProportionScan(),p,w).count)
    }
    @Test fun darkMultipleMissingAndInterruptedFramesResetProgress(){
        val s=BodyProportionScan();for(i in 0..10)feed(s,time=1000+i*80L)
        assertEquals(0,feed(s,time=1900,bright=20.0).count)
        assertEquals(1,feed(s,time=2000).count)
        assertEquals(0,s.add(listOf(joints(),joints()),listOf(world(),world()),400,800,2100,120.0).count)
        assertEquals(0,s.add(emptyList(),emptyList(),400,800,2200,120.0).count)
        feed(s,time=2300);assertEquals(1,feed(s,time=2300).count)
    }
    @Test fun movementOrUnstableRatiosCannotProduceResult(){
        val moving=BodyProportionScan();feed(moving)
        val moved=joints().map{it.copy(x=it.x+.08)}
        assertEquals(0,feed(moving,moved,time=1100).count)
        val s=BodyProportionScan()
        for(i in 0..14){val p=joints();if(i%2==0){p[23]=p[23].copy(x=.33);p[24]=p[24].copy(x=.67)}
            val u=feed(s,p,time=1000+i*250L);assertNull(u.result)
            if(i==14)assertTrue(u.progress<1.0)
        }
    }
    @Test fun noSharedStateAcrossPeopleOrNewSessions(){
        val s=BodyProportionScan();for(i in 0..20)feed(s,time=1000+i*80L)
        feed(s,p=joints().apply{this[11]=this[11].copy(confidence=0.0)},time=2700)
        assertEquals(1,feed(s,time=2800).count)
        s.reset();assertEquals(1,feed(s,time=2900).count)
    }
    @Test fun kneesAndFeetAreNotRequiredForTorsoJointRatios(){
        val p=joints().apply{for(i in 25..32)this[i]=this[i].copy(y=1.3,confidence=0.0)}
        val w=world().apply{for(i in 25..32)this[i]=this[i].copy(confidence=0.0)}
        assertEquals(15,complete(p=p,w=w).sampleCount)
        val croppedHip=joints().apply{this[24]=this[24].copy(y=1.05)}
        assertEquals(0,feed(BodyProportionScan(),croppedHip).count)
    }
    @Test fun widthJitterDoesNotInventCameraMotionForLowCentredTorso(){
        val s=BodyProportionScan();var update=BodyProportionScan.Update("")
        for(i in 0..14){
            val factor=if(i==0)1.0 else if(i%2==0).97 else 1.03
            val p=joints().map{it.copy(y=it.y+.27)}.toMutableList()
            p[11]=p[11].copy(x=.5-.15*factor);p[12]=p[12].copy(x=.5+.15*factor)
            update=feed(s,p,time=1000+i*250L)
            assertTrue("Width jitter must not be mistaken for translation",update.count>0)
        }
        assertNotNull(update.result);assertEquals(15,update.result!!.sampleCount)
    }
    @Test fun briefBorderlineConfidencePausesWithoutAddingSamplesOrInventingSuccess(){
        val s=BodyProportionScan();for(i in 0..9)feed(s,time=1000+i*250L)
        val unclear=joints().apply{this[23]=this[23].copy(confidence=.6)}
        val paused=feed(s,unclear,time=3500);assertEquals(10,paused.count);assertNull(paused.result)
        var last=paused
        for(i in 0..4)last=feed(s,time=3750+i*250L)
        assertNotNull(last.result);assertEquals(15,last.result!!.sampleCount)
        assertEquals(3750L,last.result!!.durationMs)
    }
    @Test fun sustainedUnclearOrTooManyMissesCannotReuseOldProgress(){
        val s=BodyProportionScan();for(i in 0..9)feed(s,time=1000+i*80L)
        val unclear=joints().apply{this[23]=this[23].copy(confidence=.6)}
        assertEquals(10,feed(s,unclear,time=1800).count)
        assertEquals(10,feed(s,unclear,time=1880).count)
        assertEquals(0,feed(s,unclear,time=1960).count)
        assertEquals(1,feed(s,time=2040).count)
        val repeated=BodyProportionScan()
        for(i in 0..4)feed(repeated,time=1000+i*80L)
        for(i in 0..4){assertNull(feed(repeated,unclear,time=1400+i*160L).result);feed(repeated,time=1480+i*160L)}
        assertEquals(0,feed(repeated,unclear,time=2200).count)
    }
    @Test fun adequatelyResolvedNarrowJointSpanIsAcceptedButTinyAndCroppedPeopleAreNot(){
        // 72px in a 480px image was blocked by the old 16% framing threshold.
        val p=joints().map{it.copy(x=.5+(it.x-.5)*.375,y=.5+(it.y-.5)*.60)}
        val accepted=complete(p=p)
        assertTrue(accepted.relativeSpread<=.035)
        val tiny=joints().map{it.copy(x=.5+(it.x-.5)*.30,y=.5+(it.y-.5)*.45)}
        assertEquals(0,feed(BodyProportionScan(),tiny).count)
        val close=joints().map{it.copy(x=.5+(it.x-.5)*1.8)}
        assertEquals("Step back a little; keep your head and both hips visible",feed(BodyProportionScan(),close).guidance)
    }
    @Test fun slowlyWalkingAcrossTheFrameCannotPassARollingReference(){
        val s=BodyProportionScan();var last=BodyProportionScan.Update("")
        for(i in 0..30){
            val p=joints().map{it.copy(x=it.x+i*.008)}
            last=feed(s,p,time=1000+i*250L);assertNull(last.result)
        }
        assertTrue(last.progress<1.0)
    }
    @Test fun entryMovementCanSettleWithoutKeepingItsOldFramesForever(){
        val s=BodyProportionScan();var result: BodyProportionScan.Result?=null
        for(i in 0..39){
            val offset=minOf(i/6.0,1.0)*.10
            val u=feed(s,joints().map{it.copy(x=it.x+offset)},time=1000+i*250L)
            if(u.result!=null){result=u.result;break}
        }
        assertNotNull(result);assertTrue(result!!.durationMs>=3000)
    }
    @Test fun slowPhonesCanFinishWithoutDuplicatingSamplesAndLongGapsStillReset(){
        for(step in listOf(200L,350L,700L,1000L)){
            val s=BodyProportionScan();var u=BodyProportionScan.Update("")
            for(i in 0..14){u=feed(s,time=1000+i*step);if(i<14)assertNull(u.result)}
            if(step==200L){assertNull(u.result);u=feed(s,time=4000)}
            assertNotNull("Stable slow phone, step=$step",u.result)
            assertTrue(u.result!!.sampleCount>=15);assertTrue(u.result!!.durationMs>=3000)
        }
        val s=BodyProportionScan();for(i in 0..10)feed(s,time=1000+i*350L)
        assertEquals(1,feed(s,time=6000).count)
    }
    @Test fun progressDependsOnSamplesAndTimeAndNeverAdvancesDuringAnUnclearFrame(){
        val s=BodyProportionScan();var u=feed(s)
        for(i in 1..13){u=feed(s,time=1000+i*10L);assertTrue(u.progress<.1);assertNull(u.result)}
        val before=u.progress
        val unclear=joints().apply{this[23]=this[23].copy(confidence=.6)}
        val paused=feed(s,unclear,time=1500);assertEquals(before,paused.progress,0.0);assertNull(paused.result)
        assertEquals(1,feed(s,time=4000).count) // waiting on one old pose is not evidence
    }
}
