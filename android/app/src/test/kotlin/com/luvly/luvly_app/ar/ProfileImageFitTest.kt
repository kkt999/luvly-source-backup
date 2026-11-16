package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class ProfileImageFitTest {
    private val world=listOf(Vec3(-.04f,.5f,.2f),Vec3(.04f,.5f,-.2f),Vec3(-.03f,0f,.14f),Vec3(.03f,0f,-.14f))
    private val pixels=world.map { Pair(300+it.x*400,200+it.y*400) }
    @Test fun fitsPositiveUniformScaleWithoutInventingRotationOrJoints() {
        val fit=ProfileImageFit.fit(world,pixels,200f)!!
        assertEquals(400f,fit.scale,.01f);assertEquals(0f,fit.error,.01f)
    }
    @Test fun rejectsBadJointAndMissingOrNonfiniteData() {
        assertNull(ProfileImageFit.fit(world,pixels.toMutableList().apply { this[3]=Pair(400f,200f) },200f))
        assertNull(ProfileImageFit.fit(world.take(3),pixels,200f))
        assertNull(ProfileImageFit.fit(world,pixels.toMutableList().apply { this[0]=Pair(Float.NaN,0f) },200f))
        assertNull(ProfileImageFit.fit(world,pixels,20f))
    }
    @Test fun rejectsReversedBodyAndNonUniformStretch() {
        assertNull(ProfileImageFit.fit(world,world.map { Pair(300-it.x*400,400-it.y*400) },200f))
        assertNull(ProfileImageFit.fit(world,world.map { Pair(300+it.x*2000,200+it.y*400) },200f))
    }
}
