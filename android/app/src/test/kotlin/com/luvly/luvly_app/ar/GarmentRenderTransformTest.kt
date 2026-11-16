package com.luvly.luvly_app.ar

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class GarmentRenderTransformTest {
    private val models=listOf(DressAnchors(),DressAnchors(1.45f,.97f,.40f,true,.53f,-.20f),
        DressAnchors(1.40f,.97f,.31f,false,.06f))
    private fun pose(yaw: Float=0f,y: Float=500f,pitch: Float=0f): DressPose {
        val a=Math.toRadians(yaw.toDouble()).toFloat()
        val p=Math.toRadians(pitch.toDouble()).toFloat()
        val right=Vec3(cos(a),0f,-sin(a))
        val up=Vec3(sin(a)*sin(p),cos(p),cos(a)*sin(p))
        return DressPose(300f,y,300f*cos(a),320f,0f,spatial=SpatialDressPose(
            Vec3(0f,.52f,-2.5f),right,up,1f,1f,
            PerspectiveProjection(600,900,800f,800f,300f,450f,"test"),0f))
    }
    private fun apply(m: FloatArray,p: Vec3)=Vec3(
        m[0]*p.x+m[4]*p.y+m[8]*p.z+m[12],
        m[1]*p.x+m[5]*p.y+m[9]*p.z+m[13],
        m[2]*p.x+m[6]*p.y+m[10]*p.z+m[14])
    @Test fun allModelPivotsRemainOnWearerWhileTurning() {
        for(model in models)for(yaw in listOf(-40f,0f,40f)) {
            val p=pose(yaw);val m=GarmentRenderTransform.matrix(p,model)
            val shoulder=apply(m,Vec3(0f,model.shoulderY,model.bodyZ))
            assertEquals(p.x,shoulder.x,.001f);assertEquals(p.y,shoulder.y,.001f)
            assertEquals(0f,shoulder.z,.001f)
            val hip=apply(m,Vec3(0f,model.hipY,model.bodyZ))
            assertEquals((model.shoulderY-model.hipY)*p.heightScale,shoulder.y-hip.y,.001f)
        }
    }
    @Test fun movingToBottomOfImageCannotRaiseTrainOrChangeNecklineShape() {
        for(model in models)for(yaw in listOf(-30f,0f,30f)) {
            val top=GarmentRenderTransform.matrix(pose(yaw,700f),model)
            val bottom=GarmentRenderTransform.matrix(pose(yaw,150f),model)
            for(point in listOf(Vec3(0f,1.35f,.15f),Vec3(.5f,.02f,-2.8f),Vec3(-.5f,.02f,-2.8f))) {
                val a=apply(top,point);val b=apply(bottom,point)
                assertEquals(a.x,b.x,.001f);assertEquals(a.y-550f,b.y,.001f)
                assertEquals(a.z,b.z,.001f)
            }
        }
    }
    @Test fun uncertainPitchCannotFlipUprightGownOrLiftLongTrain() {
        for(model in models)for(pitch in listOf(-24f,24f)) {
            val stable=GarmentRenderTransform.matrix(pose(20f),model)
            val noisy=GarmentRenderTransform.matrix(pose(20f,pitch=pitch),model)
            assertArrayEquals(stable,noisy,.001f)
        }
    }
    @Test fun turningRotatesRealGeometryWithoutNarrowingShouldersTwice() {
        val model=models[1]
        for(yaw in listOf(-35f,35f)) {
            val p=pose(yaw);val m=GarmentRenderTransform.matrix(p,model)
            val l=apply(m,Vec3(-.2f,model.shoulderY,model.bodyZ))
            val r=apply(m,Vec3(.2f,model.shoulderY,model.bodyZ))
            assertEquals(.4f*p.widthScale,r.x-l.x,.001f)
            assertTrue(abs(r.z-l.z)>50f)
            val front=apply(m,Vec3(0f,1.2f,model.bodyZ+.1f))
            val back=apply(m,Vec3(0f,1.2f,model.bodyZ-.1f))
            assertTrue(front.z>back.z)
        }
    }
    @Test fun inPlaneLeanAndWidthAdjustmentKeepPivotFixed() {
        val model=models[2];val p=pose().copy(roll=.2f)
        val m=GarmentRenderTransform.matrix(p,model,1.1f)
        val anchor=apply(m,Vec3(0f,model.shoulderY,model.bodyZ))
        assertEquals(p.x,anchor.x,.001f);assertEquals(p.y,anchor.y,.001f)
        val hip=apply(m,Vec3(0f,model.hipY,model.bodyZ))
        assertTrue(hip.x>anchor.x && hip.y<anchor.y)
    }
    @Test fun legacyFixtureWithoutWorldStillUsesSameFrontAnchors() {
        val p=pose().copy(spatial=null)
        assertArrayEquals(GarmentRenderTransform.matrix(p,models[0]),
            GarmentRenderTransform.matrix(pose(),models[0]),.001f)
    }
}
