package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class FrameProjectionResizeTest {
    @Test fun downsamplingPreservesViewProjectionAndOffCentrePrincipalPoint() {
        for(frame in listOf(FrameProjection(768,1024,910f,900f,370f,498f),
                            FrameProjection(1024,768,910f,900f,498f,370f))) {
            val small=frame.resized(frame.width*5/8,frame.height*5/8)
            val before=frame.forView(1080,1700)!!;val after=small.forView(1080,1700)!!
            for(point in listOf(Vec3(-.2f,.52f,-2.5f),Vec3(.2f,.52f,-2f),Vec3(.14f,0f,-3f))) {
                val a=before.project(point)!!;val b=after.project(point)!!
                assertEquals(a.first,b.first,.001f);assertEquals(a.second,b.second,.001f)
            }
        }
    }
}
