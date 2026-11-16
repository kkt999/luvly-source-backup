package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class PoseDisplaySafetyTest {
    private val anchors=DressAnchors()
    private fun points()=MutableList(33) { BodyPoint(.5f,.5f,1f) }.apply {
        this[11]=BodyPoint(.4f,.3f,1f);this[12]=BodyPoint(.6f,.3f,1f)
        this[23]=BodyPoint(.43f,.5f,1f);this[24]=BodyPoint(.57f,.5f,1f)
    }
    private val held=PoseAlignment.align(points(),600,900,600,900,anchors)!!
    private fun hide(p: List<BodyPoint>)=PoseDisplaySafety.shouldHide(held,p,600,900,600,900,anchors)
    @Test fun reportsSpecificDisplaySafetyReasonWithoutChangingThresholds() {
        fun reason(p: List<BodyPoint>)=PoseDisplaySafety.hideReason(held,p,600,900,600,900,anchors)
        assertNull(reason(points()))
        assertEquals("shoulder_position_changed",reason(points().map { it.copy(x=it.x+.1f) }))
        assertEquals("body_out_of_frame",reason(points().apply { this[23]=this[23].copy(y=1.1f) }))
        assertEquals("torso_scale_changed",reason(points().apply {
            this[23]=this[23].copy(y=.6f);this[24]=this[24].copy(y=.6f)
        }))
    }
    @Test fun freshMovementDisprovesOldPositionEvenWithoutWorldPose() {
        assertFalse(hide(points()))
        assertTrue(hide(points().map { it.copy(x=it.x+.1f) }))
        assertTrue(hide(points().apply { this[23]=this[23].copy(y=1.1f) }))
        assertTrue(hide(points().apply {
            this[23]=this[23].copy(y=.6f);this[24]=this[24].copy(y=.6f)
        }))
    }
    @Test fun tinyJitterNarrowShouldersOrUnknownBodyDoNotDisproveHeldPosition() {
        assertFalse(hide(points().map { it.copy(x=it.x+.002f) }))
        assertFalse(hide(points().apply {
            this[11]=this[11].copy(x=.49f);this[12]=this[12].copy(x=.51f)
        }))
        assertFalse(hide(emptyList()))
        assertFalse(hide(points().map { it.copy(confidence=.2f,x=it.x+.1f) }))
    }
    @Test fun suppressionKeepsOutlierHistoryButNeverAuthorizesCapture() {
        val f=DressPoseFilter();f.observe(held,1000,.4f)
        val next=held.copy(x=held.x+300)
        assertFalse(f.observe(next,1100,.4f).accepted)
        f.suppressHeldDisplay()
        assertNull(f.displayAt(1100).pose)
        assertNull(f.observe(next,1200,.4f).pose)
        val recovered=f.observe(next,1300,.4f)
        assertTrue(recovered.accepted);assertEquals(next,recovered.pose)
        assertNotNull(f.displayAt(1300).pose)
    }
    @Test fun suppressionDoesNotExtendExpiryOrLeakThroughReset() {
        val f=DressPoseFilter();f.observe(held,1000,.4f);f.suppressHeldDisplay()
        assertNull(f.displayAt(1500).pose);assertNull(f.displayAt(2000).pose)
        f.reset();assertTrue(f.observe(held,2100,.4f).accepted)
        assertNotNull(f.displayAt(2100).pose)
    }
}
