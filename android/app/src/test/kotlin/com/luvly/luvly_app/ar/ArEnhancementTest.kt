package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.*

class ArEnhancementTest {
    private fun pose(x: Float=300f,yaw: Float=0f): DressPose {
        val angle=Math.toRadians(yaw.toDouble()).toFloat()
        return DressPose(x,400f,500f,500f,0f,spatial=SpatialDressPose(
            Vec3(0f,.5f,-2f),Vec3(cos(angle),0f,-sin(angle)),Vec3(0f,1f,0f),
            1f,1f,FrameProjection.estimated(600,900).forView(600,900)!!,0f))
    }
    /** Locked 2082 normal-tracking coefficients, for controlled before/after comparison.
     * These sequences deliberately exclude outliers/dropouts (covered elsewhere).
     */
    private fun legacy(old: DressPose,next: DressPose,dt: Float): DressPose {
        val span=max(35f,old.widthScale*.4f)
        val speed=max(hypot(next.x-old.x,next.y-old.y)/span,
            max(abs(next.widthScale/old.widthScale-1),abs(next.heightScale/old.heightScale-1)))/dt
        val cutoff=(.65f+speed*2.5f).coerceIn(.65f,7f)
        val alpha=(1-exp(-2*PI.toFloat()*cutoff*dt)).coerceIn(.08f,.95f)
        return next.copy(x=old.x+alpha*(next.x-old.x),
            spatial=old.spatial!!.blend(next.spatial!!,alpha,alpha))
    }
    private fun rms(values: List<Float>)=sqrt(values.map { it.toDouble().pow(2) }.average())

    @Test fun benchmarkJitterTurnLagAndTranslationAtMultipleRates() {
        for(step in listOf(33L,66L,100L)) {
            fun run(moving: Boolean): Pair<List<Float>,List<Float>> {
                val filter=DressPoseFilter()
                var old=pose(); filter.observe(old,1000,.4f)
                val a=mutableListOf<Float>(); val b=mutableListOf<Float>()
                for(i in 1..180) {
                    val t=i*step/1000f
                    val truth=if(moving) 300f+45f*sin(t*1.2f) else 300f
                    val raw=pose(truth+3f*sin(i*2.1f))
                    old=legacy(old,raw,step/1000f)
                    val result=filter.observe(raw,1000+i*step,.4f).pose!!
                    if(i>30) { a.add(old.x-truth);b.add(result.x-truth) }
                }
                return a to b
            }
            val quiet=run(false);val motion=run(true)
            val filter=DressPoseFilter(); var old=pose();filter.observe(old,1000,.4f)
            val oldTurn=mutableListOf<Float>();val newTurn=mutableListOf<Float>()
            for(i in 1..180) {
                val truth=30f*sin(i*step/1000f*1.2f)
                val raw=pose(yaw=truth)
                old=legacy(old,raw,step/1000f)
                val result=filter.observe(raw,1000+i*step,.4f).pose!!
                if(i>30) { oldTurn.add(old.spatial!!.yawDegrees-truth);newTurn.add(result.spatial!!.yawDegrees-truth) }
            }
            println("AR_BENCH step=${step}ms stationaryRmsPx ${rms(quiet.first)} -> ${rms(quiet.second)}; movingRmsPx ${rms(motion.first)} -> ${rms(motion.second)}; yawRmsDeg ${rms(oldTurn)} -> ${rms(newTurn)}")
            assertTrue("stationary jitter $step",rms(quiet.second)<rms(quiet.first))
            assertTrue("turn responsiveness $step",rms(newTurn)<rms(oldTurn)*.85)
            assertTrue("translation regression budget $step",rms(motion.second)<rms(motion.first)*1.25)
        }
    }

    @Test fun invalidPoseNeverReachesRendererOrReadiness() {
        for(bad in listOf(pose(Float.NaN),pose().copy(widthScale=0f),pose().copy(roll=Float.POSITIVE_INFINITY),
            pose().copy(spatial=pose().spatial!!.copy(right=Vec3(Float.NaN,0f,0f))))) {
            val filter=DressPoseFilter()
            assertFalse(filter.observe(bad,1000,.4f).accepted)
            assertNull(filter.displayAt(1000).pose)
            filter.observe(pose(),1100,.4f)
            assertFalse(filter.observe(bad,1200,.4f).accepted)
            assertNull(filter.displayAt(2200).pose)
        }
    }
    @Test fun turningDoesNotAmplifyPositionNoiseAndOutlierDoesNotPoisonVelocity() {
        val a=DressPoseFilter();val b=DressPoseFilter()
        a.observe(pose(),1000,.4f);b.observe(pose(),1000,.4f)
        val first=a.observe(pose(x=302f,yaw=20f),1100,.4f).pose!!
        val second=b.observe(pose(x=302f),1100,.4f).pose!!
        assertEquals(second.x,first.x,.001f)
        assertTrue(first.spatial!!.yawDegrees>second.spatial!!.yawDegrees)
        assertFalse(a.observe(pose(x=900f),1200,.4f).accepted)
        val restored=a.observe(pose(x=302f,yaw=20f),1300,.4f)
        assertTrue(restored.accepted);assertTrue(restored.pose!!.x in 300f..303f)
    }
    @Test fun irregularIntervalsAndShapeNoiseRemainBounded() {
        val f=DressPoseFilter();f.observe(pose(),1000,.4f)
        var time=1000L
        for(i in 1..160) {
            time+=listOf(33L,70L,100L,50L)[i%4]
            val p=pose(x=300f+2f*sin(i.toFloat())).copy(widthScale=500f+4f*sin(i*1.7f))
            val result=f.observe(p,time,.4f)
            assertTrue(result.accepted)
            assertTrue(result.pose!!.x in 298f..302f)
            assertTrue(result.pose.widthScale in 496f..504f)
        }
    }
    private fun body()=MutableList(33){BodyPoint(.5f,.5f,1f)}.apply {
        this[11]=BodyPoint(.3f,.25f,1f);this[12]=BodyPoint(.7f,.25f,1f)
        this[23]=BodyPoint(.4f,.55f,1f);this[24]=BodyPoint(.6f,.55f,1f)
    }
    @Test fun guidanceDistinguishesMissingClippedOccludedAndSmallBodies() {
        fun assess(p: List<BodyPoint>)=PoseGuidance.assess(p,600,900,600,900)
        assertEquals(PoseGuidance.Issue.NO_BODY,assess(emptyList()))
        assertEquals(PoseGuidance.Issue.CLEAR,assess(body()))
        assertEquals(PoseGuidance.Issue.CLIPPED,assess(body().apply { this[11]=this[11].copy(x=-.1f) }))
        assertEquals(PoseGuidance.Issue.SHOULDERS,assess(body().apply { this[12]=this[12].copy(confidence=.2f) }))
        assertEquals(PoseGuidance.Issue.HIPS,assess(body().apply { this[24]=this[24].copy(confidence=.2f) }))
        assertEquals(PoseGuidance.Issue.TOO_FAR,assess(body().map { it.copy(x=.5f+(it.x-.5f)*.05f,y=.5f+(it.y-.5f)*.05f) }))
    }
    @Test fun diagnosticsAreWindowedAndNeverClaimBodyMeasurements() {
        val metrics=TrackingDiagnostics()
        metrics.observe(1000,900,true,2f);metrics.observe(1100,1000,false,null)
        val text=metrics.description(1100)
        assertTrue(text.contains("10.0/s"));assertTrue(text.contains("1/2"))
        assertTrue(text.contains("100 ms"));assertTrue(text.contains("2.0 px"))
        assertTrue(text.contains("Not body measurements"))
        assertTrue(metrics.description(4000).contains("Waiting"))
        metrics.reset();assertTrue(metrics.description(1100).contains("Waiting"))
    }
}
