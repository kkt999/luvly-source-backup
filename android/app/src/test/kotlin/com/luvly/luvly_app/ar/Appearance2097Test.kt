package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test

class Appearance2097Test {
    private fun points()=MutableList(33){BodyPoint(.5f,.5f,1f,0f)}.apply {
        this[11]=BodyPoint(.3f,.25f,1f,0f);this[12]=BodyPoint(.7f,.25f,1f,0f)
        this[23]=BodyPoint(.4f,.65f,1f,0f);this[24]=BodyPoint(.6f,.65f,1f,0f)
        this[13]=BodyPoint(.32f,.45f,1f,-.15f);this[15]=BodyPoint(.52f,.45f,1f,-.2f)
    }
    private fun pose()=DressPose(300f,500f,300f,320f,0f,spatial=SpatialDressPose(
        Vec3(0f,.5f,-2f),Vec3(1f,0f,0f),Vec3(0f,1f,0f),1f,1f,
        PerspectiveProjection(600,900,800f,800f,300f,450f,"test"),0f))
    private fun world()=MutableList(33){WorldBodyPoint(0f,0f,0f,1f)}.apply {
        this[11]=WorldBodyPoint(-.2f,-.5f,0f,1f);this[12]=WorldBodyPoint(.2f,-.5f,0f,1f)
        this[13]=WorldBodyPoint(-.2f,-.2f,0f,1f);this[14]=WorldBodyPoint(.2f,-.2f,0f,1f)
    }
    @Test fun independentSleevesRaisedArmAndNeutralArm() {
        val w=world();w[13]=w[13].copy(y=-.8f)
        val (left,right)=SleeveFit.offsets(pose(),w,points())
        assertEquals(.25f,left.y,.001f);assertEquals(0f,right.y,.001f)
        assertEquals(0f,left.x,.001f);assertEquals(0f,left.z,.001f)
    }
    @Test fun forwardArmMovesDepthRatherThanPretendingToBeSideways() {
        val w=world();w[13]=w[13].copy(y=-.5f,z=-.3f)
        val left=SleeveFit.offsets(pose(),w,points()).first
        assertTrue(left.z>.28f);assertTrue(left.y>.12f);assertEquals(0f,left.x,.001f)
    }
    @Test fun uncertainMissingAndImpossibleArmsReturnNeutral() {
        val w=world();w[13]=w[13].copy(y=-.8f,confidence=.2f)
        assertEquals(SleeveFit.neutral,SleeveFit.offsets(pose(),w,points()).first)
        w[13]=w[13].copy(confidence=1f,y=-5f)
        assertEquals(SleeveFit.neutral,SleeveFit.offsets(pose(),w,points()).first)
        assertEquals(SleeveFit.neutral,SleeveFit.offsets(pose(),emptyList(),points()).first)
    }
    @Test fun mirrorKeepsCorrectVisibleSleeveAndLimitsFolding() {
        val w=world();w[13]=w[13].copy(y=-.8f)
        val mirrored=w.map { it.copy(x=-it.x) }
        val sleeves=SleeveFit.offsets(pose(),mirrored,points())
        assertEquals(0f,sleeves.first.y,.001f);assertEquals(.25f,sleeves.second.y,.001f)
        w[13]=w[13].copy(x=.05f,y=-.4f)
        assertTrue(SleeveFit.offsets(pose(),w,points()).first.x<=.025f/.12f+.001f)
    }
    @Test fun filterPreservesSleeveChannelsAndRejectsNaN() {
        val f=DressPoseFilter();val p=pose();f.observe(p,1000,.4f)
        val next=f.observe(p.copy(sleeveLeft=Vec3(0f,1f,0f)),1100,.4f).pose!!
        assertTrue(next.sleeveLeft.y in .01f.. .99f)
        assertFalse(f.observe(p.copy(sleeveRight=Vec3(Float.NaN,0f,0f)),1200,.4f).accepted)
    }
    @Test fun colourMatteRejectsUniformBackgroundAndBehindArms() {
        assertNull(FastArmMask.pixels(IntArray(600*900){0xffaaaaaa.toInt()},600,900,points()))
        val p=points();p[13]=p[13].copy(z=.2f);p[15]=p[15].copy(z=.3f)
        assertNull(FastArmMask.pixels(IntArray(600*900){0xffaa7855.toInt()},600,900,p))
    }
    @Test fun colourMatteLearnsDifferentArmColoursWithoutRevealingBackground() {
        for(colour in listOf(0xff573a2d.toInt(),0xffb77f65.toInt(),0xffe0b7a0.toInt())) {
            val rgb=IntArray(600*900){0xff99bbaa.toInt()}
            for(y in 395..415)for(x in 185..320)rgb[y*600+x]=colour
            val mask=FastArmMask.pixels(rgb,600,900,points())!!
            assertTrue((mask[405*600+250] ushr 24)>200)
            assertEquals(0,mask[430*600+250] ushr 24)
            assertEquals(0,mask[200*600+300] ushr 24)
        }
    }
}
