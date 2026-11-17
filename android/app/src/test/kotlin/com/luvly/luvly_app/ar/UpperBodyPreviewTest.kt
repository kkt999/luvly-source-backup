package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*

class UpperBodyPreviewTest {
    private val anchors=DressAnchors()
    private fun body(hipY: Float=1.1f,scale: Float=1f,x: Float=.5f)=MutableList(33) { BodyPoint(x,.2f,1f) }.apply {
        this[0]=BodyPoint(x,.23f,1f);this[2]=BodyPoint(x-.04f,.20f,1f);this[5]=BodyPoint(x+.04f,.20f,1f)
        this[11]=BodyPoint(x-.28f*scale,.48f,1f);this[12]=BodyPoint(x+.28f*scale,.48f,1f)
        this[23]=BodyPoint(x-.15f,hipY,.8f);this[24]=BodyPoint(x+.15f,hipY,.8f)
    }
    private fun world(yaw: Float=0f)=MutableList(33) { WorldBodyPoint(0f,0f,0f,1f) }.apply {
        val a=Math.toRadians(yaw.toDouble()).toFloat()
        this[11]=WorldBodyPoint(-.20f*cos(a),-.4f,-.20f*sin(a),1f)
        this[12]=WorldBodyPoint(.20f*cos(a),-.4f,.20f*sin(a),1f)
    }
    private fun fit(preview: UpperBodyPreview=UpperBodyPreview(),p: List<BodyPoint> = body(),
                    w: List<WorldBodyPoint> = world(),now: Long=1000)=
        preview.register(p,w,600,900,600,900,anchors,FrameProjection.estimated(600,900),now)

    @Test fun coldStartNeedsNoHipOrFootCalibration() {
        val p=body();assertNull(PoseAlignment.align(p,600,900,600,900))
        val pose=fit(p=p)!!
        assertTrue(UpperBodyPreview.isUpper(pose));assertTrue(pose.unprojectedWidth)
        assertEquals(300f,pose.x,.01f);assertEquals(468f,pose.y,.01f)
        assertEquals(pose.widthScale,pose.heightScale,.01f)
    }
    @Test fun adaptiveWrapFollowsVisibleElbowWithoutInventingTorsoMeasurements() {
        val p=body().apply {this[13]=BodyPoint(.15f,.55f,1f);this[14]=this[14].copy(confidence=0f)}
        val w=world().apply {this[13]=WorldBodyPoint(-.4f,-.3f,-.1f,1f)}
        val a=anchors.copy(adaptiveFit=true)
        fun register()=UpperBodyPreview().register(p,w,600,900,600,900,a,
            FrameProjection.estimated(600,900),1000)!!
        val pose=register()
        assertTrue(pose.sleeveLeft.length()>0f)
        assertEquals(SleeveFit.neutral,pose.sleeveRight)
        assertEquals(0f,pose.waistFit,0f);assertEquals(0f,pose.chestFit,0f)
        assertEquals(pose.widthScale,pose.heightScale,.01f)
        p[13]=p[13].copy(confidence=.2f)
        assertEquals(SleeveFit.neutral,register().sleeveLeft)
    }
    @Test fun nonAdaptiveModelKeepsNeutralWrap() {
        val p=body().apply {this[13]=BodyPoint(.15f,.55f,1f)}
        val w=world().apply {this[13]=WorldBodyPoint(-.4f,-.3f,-.1f,1f)}
        val pose=fit(p=p,w=w)!!
        assertEquals(SleeveFit.neutral,pose.sleeveLeft)
        assertEquals(SleeveFit.neutral,pose.sleeveRight)
    }
    @Test fun faceOnlyMissingShoulderAndHiddenFaceAreRejected() {
        for(i in listOf(0,2,5,11,12)) {
            val p=body();p[i]=p[i].copy(confidence=.1f)
            assertNull("Missing joint $i",fit(p=p))
        }
        assertNull(fit(p=body().apply { this[11]=this[11].copy(x=-.1f) }))
        assertNull(fit(p=body().apply { this[11]=this[11].copy(y=.9f);this[12]=this[12].copy(y=.9f) }))
    }
    @Test fun visibleHipsUseFullTorsoPath() { assertNull(fit(p=body(.85f))) }
    @Test fun occludedHipsDoNotEnableFallbackWhenBodyFitsInFrame() {
        val p=body(.85f,.6f).apply { this[23]=this[23].copy(confidence=.1f);this[24]=this[24].copy(confidence=.1f) }
        assertFalse(UpperBodyPreview.eligible(p,600,900));assertNull(fit(p=p))
    }
    @Test fun lowConfidenceHipsQualifyOnlyAtBottomCrop() {
        val p=body(.9f,1.05f).apply {
            this[11]=this[11].copy(y=.55f);this[12]=this[12].copy(y=.55f)
            this[23]=this[23].copy(confidence=.1f);this[24]=this[24].copy(confidence=.1f)
        }
        assertNotNull(fit(p=p))
    }
    @Test fun oneHipCrossingTheBottomEdgeKeepsTheUpperBodyPreview() {
        val p=body(.94f,1.05f).apply {
            this[11]=this[11].copy(y=.55f);this[12]=this[12].copy(y=.55f)
            this[24]=this[24].copy(y=1.01f,confidence=.35f)
        }
        assertNotNull(fit(p=p))
        p[23]=p[23].copy(y=.76f)
        assertNull(fit(p=p))
    }
    @Test fun duplicateCropsCanConfirmASingleUpperBody() {
        val lock=BodyTargetLock()
        val p=body()
        val duplicate=body(x=.51f)
        for(now in listOf(1000L,1200L))
            assertEquals("target_confirming",lock.select(listOf(p,duplicate),600,900,now).reason)
        assertEquals("target_acquired",lock.select(listOf(duplicate,p),600,900,1400L).reason)
    }
    @Test fun requiresRealCurrentWorldShouldersAndBoundedTurn() {
        assertNull(fit(w=emptyList()));assertNull(fit(w=world(65f)))
        assertNull(fit(w=world().apply { this[11]=this[11].copy(confidence=.3f) }))
        assertNotNull(fit(w=world(30f)))
    }
    @Test fun invalidCoordinatesNeverReachRenderer() {
        assertNull(fit(p=body().apply {this[11]=this[11].copy(x=Float.NaN)}))
        assertNull(fit(w=world().apply {this[12]=this[12].copy(z=Float.NaN)}))
        assertNull(fit(p=body().apply {this[23]=this[23].copy(y=Float.NaN)}))
    }
    @Test fun zoomScalesGownInsteadOfFreezingLastFullBodyPose() {
        val a=fit()!!;val b=fit(p=body(scale=1.15f))!!
        assertEquals(1.15f,b.widthScale/a.widthScale,.001f)
        assertEquals(1.15f,b.heightScale/a.heightScale,.001f)
    }
    @Test fun recentFullTorsoProportionsExpireAndResetWithTarget() {
        val u=UpperBodyPreview();val full=fit()!!.copy(heightScale=fit()!!.widthScale*1.2f,
            waistFit=.4f,spatial=fit()!!.spatial!!.copy(registrationMode="perspective"))
        u.remember(full,1000)
        val close=fit(u,now=2000)!!
        assertEquals(1.2f,close.heightScale/close.widthScale,.001f);assertEquals(.4f,close.waistFit,.001f)
        assertEquals(1f,fit(u,now=7000)!!.let {it.heightScale/it.widthScale},.001f)
        u.reset();assertEquals(0f,fit(u,now=2200)!!.waistFit,.001f)
    }
    @Test fun upperSamplesCannotOverwriteFullTorsoReference() {
        val u=UpperBodyPreview();u.remember(fit()!!.copy(heightScale=2000f),1000)
        val p=fit(u,now=1100)!!;assertEquals(p.widthScale,p.heightScale,.001f)
    }
    @Test fun canAcquireCroppedTargetAndContinueToFullTorsoAndBack() {
        val t=BodyTargetLock()
        for(time in listOf(1000L,1150L))assertNull(t.select(listOf(body()),600,900,time).index)
        assertEquals(0,t.select(listOf(body()),600,900,1300).index)
        val full=body(.93f)
        assertEquals(0,t.select(listOf(full),600,900,1500).index)
        assertEquals(0,t.select(listOf(body()),600,900,1700).index)
    }
    @Test fun canRecoverFromFullTorsoToCloseCropAndBackAfterLosingLock() {
        val t=BodyTargetLock()
        val full=body(.71f,scale=.48f)
        val crop=body()
        fun select(p: List<BodyPoint>, now: Long)=t.select(listOf(p),600,900,now)
        select(full,1000);select(full,1400)
        assertEquals("target_acquired",select(full,1800).reason)
        assertEquals("target_lost",select(crop,2200).reason)
        select(crop,3400);select(crop,3800)
        assertEquals("target_reacquired",select(crop,4200).reason)
        select(full,5800);select(full,6200)
        assertEquals("target_reacquired",select(full,6600).reason)
    }
    @Test fun mirrorAmbiguityAndStaleFramesStillBlockUpperTarget() {
        val t=BodyTargetLock()
        assertEquals("target_ambiguous",t.select(listOf(body(x=.47f),body(x=.53f)),600,900,1000).reason)
        assertEquals("target_stale",t.select(listOf(body()),600,900,1000).reason)
    }
    @Test fun lostUpperTargetCannotTransferToDifferentPerson() {
        val t=BodyTargetLock()
        for(time in listOf(1000L,1150L,1300L))t.select(listOf(body()),600,900,time)
        for(time in 1500L..4000L step 200)
            assertNull(t.select(listOf(body(scale=.6f,x=.2f)),600,900,time).index)
    }
    @Test fun croppedHipsDoNotHideUpperPoseButMovedShouldersDo() {
        val pose=fit()!!
        assertNull(PoseDisplaySafety.hideReason(pose,body(),600,900,600,900,anchors))
        val moved=body().map {it.copy(x=it.x+.15f)}
        assertNotNull(PoseDisplaySafety.hideReason(pose,moved,600,900,600,900,anchors))
    }
    @Test fun filterSmoothsModeSwitchAndExpiresWhenInputStops() {
        val f=DressPoseFilter();val close=fit()!!
        val full=close.copy(heightScale=close.heightScale*.95f,spatial=close.spatial!!.copy(registrationMode="perspective"))
        assertTrue(f.observe(full,1000,anchors.shoulderWidth).accepted)
        val r=f.observe(close,1200,anchors.shoulderWidth)
        assertTrue(r.accepted);assertTrue(r.pose!!.heightScale in full.heightScale..close.heightScale)
        assertTrue(UpperBodyPreview.isUpper(r.pose))
        assertNull(f.displayAt(2201).pose)
    }
}
