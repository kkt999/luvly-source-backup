package com.luvly.luvly_app.ar

import org.junit.Assert.*
import org.junit.Test

class RenderViewportTest {
    @Test fun usesValidSurfaceSize()=assertEquals(720 to 960,RenderViewport.resolve(720,960,1080,1920))
    @Test fun alreadyAttachedZeroSizeUsesTextureSize()=assertEquals(1080 to 1600,RenderViewport.resolve(0,0,1080,1600))
    @Test fun partiallyInvalidCallbackUsesBothViewDimensions()=assertEquals(1080 to 1600,RenderViewport.resolve(0,400,1080,1600))
    @Test fun beforeLayoutWaitsInsteadOfProjectingZero()=assertNull(RenderViewport.resolve(0,0,0,0))
    @Test fun invalidSizeCannotReachNativeProjection()=assertNull(RenderViewport.resolve(-1,900,720,0))
}
