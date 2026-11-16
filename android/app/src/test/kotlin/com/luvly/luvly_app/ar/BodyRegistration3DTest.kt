package com.luvly.luvly_app.ar

import kotlin.math.*
import org.junit.Assert.*
import org.junit.Test

class BodyRegistration3DTest {
    private val anchors=DressAnchors(1.4f,.97f,.31f,true)
    private val frame=FrameProjection(600,900,800f,800f,source="synthetic-known-lens")
    private data class Input(val image: MutableList<BodyPoint>,val world: MutableList<WorldBodyPoint>)
    private fun input(yaw: Float=0f,depth: Float=2.5f,offsetX: Float=0f,mirror: Boolean=false,pitch: Float=0f): Input {
        val source=MutableList(33){Vec3(0f,0f,0f)}
        source[0]=Vec3(0f,.72f,0f)
        source[11]=Vec3(-.2f,.52f,0f);source[12]=Vec3(.2f,.52f,0f)
        source[23]=Vec3(-.14f,0f,0f);source[24]=Vec3(.14f,0f,0f)
        for(i in listOf(27,28,31,32))source[i]=Vec3(if(i%2==0).1f else -.1f,-.9f,0f)
        val angle=Math.toRadians(yaw.toDouble()).toFloat()
        val lean=Math.toRadians(pitch.toDouble()).toFloat()
        val rotated=source.map {
            val y=it.y*cos(lean)-it.z*sin(lean);val z=it.y*sin(lean)+it.z*cos(lean)
            Vec3((it.x*cos(angle)+z*sin(angle))*(if(mirror)-1 else 1),y,-it.x*sin(angle)+z*cos(angle))
        }
        val p=frame.forView(600,900)!!
        val points=rotated.map {
            val xy=p.project(it+Vec3(offsetX,0f,-depth))!!
            BodyPoint(xy.first/600,1-xy.second/900,1f)
        }.toMutableList()
        return Input(points,rotated.map { WorldBodyPoint(it.x,-it.y,-it.z,1f) }.toMutableList())
    }
    private fun register(data: Input,viewW: Int=600,viewH: Int=900): DressPose? {
        val base=PoseAlignment.align(data.image,600,900,viewW,viewH,anchors) ?: return null
        return BodyRegistration3D.register(base,data.image,data.world,600,900,viewW,viewH,anchors,frame)
    }
    @Test fun solvesKnownCameraTranslationAndBodyScale() {
        val pose=register(input(offsetX=.2f))!!.spatial!!
        assertEquals(.2f,pose.shoulder.x,.0001f)
        assertEquals(.52f,pose.shoulder.y,.0001f)
        assertEquals(-2.5f,pose.shoulder.z,.0001f)
        assertEquals(.4f/.31f,pose.widthScale,.0001f)
        assertEquals(.52f/.43f,pose.heightScale,.0001f)
        assertEquals(0f,pose.errorPixels,.001f)
        assertEquals(1f,pose.forward.z,.0001f)
    }
    @Test fun movingCloserChangesDepthNotTheUnderlyingGarmentWidth() {
        val near=register(input(depth=2f))!!.spatial!!
        val far=register(input(depth=3.5f))!!.spatial!!
        assertEquals(near.widthScale,far.widthScale,.0001f)
        assertEquals(-2f,near.shoulder.z,.0001f);assertEquals(-3.5f,far.shoulder.z,.0001f)
        fun span(p: SpatialDressPose): Float {
            val a=p.projection.project(p.transform(Vec3(-.155f,1.4f,0f),1.4f))!!
            val b=p.projection.project(p.transform(Vec3(.155f,1.4f,0f),1.4f))!!
            return b.first-a.first
        }
        assertEquals(1.75f,span(near)/span(far),.001f)
    }
    @Test fun leftAndRightTurnsRotateTheActualModelWithoutDoubleNarrowing() {
        val front=register(input())!!.spatial!!
        for(angle in listOf(-40f,40f)) {
            val p=register(input(yaw=angle))!!.spatial!!
            assertEquals(angle,p.yawDegrees,.001f)
            assertEquals(front.widthScale,p.widthScale,.001f)
            val left=p.transform(Vec3(-.155f,1.4f,0f),1.4f)
            val right=p.transform(Vec3(.155f,1.4f,0f),1.4f)
            assertTrue(abs(left.z-right.z)>.2f)
            assertEquals(.4f,(right-left).length(),.001f)
        }
    }
    @Test fun modelShoulderAnchorsReprojectOntoTheirImageLandmarks() {
        val data=input(yaw=35f,offsetX=-.15f)
        val p=register(data)!!.spatial!!
        for((i,x) in listOf(Pair(11,-.155f),Pair(12,.155f))) {
            val result=p.projection.project(p.transform(Vec3(x,1.4f,0f),1.4f))!!
            assertEquals(data.image[i].x*600,result.first,.01f)
            assertEquals((1-data.image[i].y)*900,result.second,.01f)
        }
    }
    @Test fun mirrorReversesYawAndKeepsPositiveScaleAndFrontFacingFrame() {
        val a=register(input(yaw=30f))!!.spatial!!
        val b=register(input(yaw=30f,mirror=true))!!.spatial!!
        assertEquals(-a.yawDegrees,b.yawDegrees,.001f)
        assertEquals(a.widthScale,b.widthScale,.001f)
        assertTrue(b.forward.z>0 && b.right.x>0)
    }
    @Test fun slightLeanUsesThirdDimensionButFullSideAndLargeLeanAreRejected() {
        val p=register(input(pitch=15f))!!.spatial!!
        assertTrue(p.up.z>.2f)
        assertNull(register(input(pitch=40f)))
        assertNull(register(input(yaw=65f)))
    }
    @Test fun fitCenterLetterboxingDoesNotChangeSolvedPhysicalPose() {
        val a=register(input(yaw=-20f))!!.spatial!!
        val b=register(input(yaw=-20f),1000,900)!!.spatial!!
        val c=register(input(yaw=-20f),600,1400)!!.spatial!!
        assertEquals(a.shoulder.x,b.shoulder.x,.0001f)
        assertEquals(a.shoulder.z,c.shoulder.z,.0001f)
        assertEquals(500f,b.projection.cx,0f);assertEquals(700f,c.projection.cy,0f)
    }
    @Test fun invalidOrMissingWorldDataNeverBecomesInventedDepth() {
        assertNull(register(input().apply { world.clear() }))
        assertNull(register(input().apply { world[11]=world[11].copy(confidence=.2f) }))
        assertNull(register(input().apply { world[12]=world[12].copy(z=Float.NaN) }))
        assertNull(register(input().apply { world[12]=world[11] }))
    }
    @Test fun inconsistent2dAnd3dCorrespondencesAreRejected() {
        val data=input()
        data.world[23]=data.world[23].copy(x=-.65f)
        assertNull(register(data))
    }
    @Test fun transformMatrixUsesShoulderPivotAndRightHandedBasis() {
        val p=register(input(yaw=25f))!!.spatial!!
        val m=p.modelMatrix(1.4f)
        val point=Vec3(m[4]*1.4f+m[12],m[5]*1.4f+m[13],m[6]*1.4f+m[14])
        assertEquals(p.shoulder.x,point.x,.0001f);assertEquals(p.shoulder.y,point.y,.0001f)
        assertEquals(p.shoulder.z,point.z,.0001f)
        assertEquals(1f,p.right.cross(p.up).dot(p.forward),.0001f)
    }
    @Test fun threeDimensionalJitterIsSmoothedAndBasisStaysOrthonormal() {
        val a=register(input())!!;val b=register(input(yaw=20f,depth=2.4f))!!
        val filter=DressPoseFilter();filter.observe(a,1000,.31f)
        val shown=filter.observe(b,1100,.31f).pose!!.spatial!!
        assertTrue(shown.yawDegrees in .1f..19.9f)
        assertTrue(shown.shoulder.z in -2.5f..-2.4f)
        assertEquals(1f,shown.right.length(),.0001f);assertEquals(1f,shown.up.length(),.0001f)
        assertEquals(0f,shown.right.dot(shown.up),.0001f)
    }
    @Test fun oneFrameOrientationJumpDoesNotFlipTheGown() {
        val a=register(input(yaw=-20f))!!;val b=register(input(yaw=25f))!!
        val filter=DressPoseFilter();filter.observe(a,1000,.31f)
        val shown=filter.observe(b,1100,.31f)
        assertFalse(shown.accepted);assertEquals(a,shown.pose)
    }
    @Test fun boundedProfileImageFitRequiresExplicitRecoveryAndRealWorldJoints() {
        // Deliberately mismatched lens; not a real-person accuracy benchmark.
        val data=input(yaw=80f)
        for(i in data.image.indices) {
            val p=data.world[i].cameraVector()
            data.image[i]=BodyPoint((300+p.x*400)/600,1-(450+p.y*400)/900,1f)
        }
        val base=PoseAlignment.align(data.image,600,900,600,900,anchors,true)!!
        val approximateLens=FrameProjection(600,900,250f,250f)
        fun fit(recovery: Boolean)=BodyRegistration3D.register(base,data.image,data.world,
            600,900,600,900,anchors,approximateLens,1f,false,recovery)
        assertNull(fit(false))
        val pose=fit(true)!!;val p=pose.spatial!!
        assertEquals("image-anchored-profile",p.registrationMode)
        assertEquals(80f,p.yawDegrees,.01f)
        assertTrue(p.perspectiveErrorPixels>208*.18f)
        assertTrue(p.errorPixels<1f)
        assertTrue(GarmentRenderTransform.matrix(pose,anchors).all { it.isFinite() })
        data.world[23]=data.world[23].copy(confidence=.1f)
        assertNull(fit(true))
        data.world.clear();assertNull(fit(true))
    }

    @Test fun lensEstimateHandlesRotationCropZoomAndUnavailableMetadata() {
        val lens=SensorLens(6.4f,4.8f,4f)
        val raw=lens.frame(960,720,0,1f)
        assertEquals(600f,raw.fx,.001f)
        val portrait=lens.frame(960,720,90,2f)
        assertEquals(720,portrait.width);assertEquals(960,portrait.height)
        assertEquals(1200f,portrait.fx,.001f)
        val crop=lens.frame(1280,720,0,1f)
        assertEquals(800f,crop.fx,.001f)
        assertEquals("estimated-fov",SensorLens(0f,0f,0f).frame(960,720,90,1f).source)
        assertNull(FrameProjection(600,900,Float.NaN,800f).forView(600,900))
    }
}
