package com.luvly.luvly_app.ar

/** UiHelper 1.56 can report (0,0) when attaching to an already-available TextureView. */
object RenderViewport {
    fun resolve(width: Int,height: Int,viewWidth: Int,viewHeight: Int): Pair<Int,Int>? = when {
        width>0 && height>0 -> width to height
        viewWidth>0 && viewHeight>0 -> viewWidth to viewHeight
        else -> null // Wait for layout; never send a degenerate frustum to native Filament.
    }
}
