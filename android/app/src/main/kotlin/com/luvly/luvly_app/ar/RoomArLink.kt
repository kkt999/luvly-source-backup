package com.luvly.luvly_app.ar

import java.net.URI
import java.net.URLEncoder

/** A separate world-placement experience; never a body-tracking fallback. */
object RoomArLink {
    const val BROWSER_PACKAGE = "com.android.chrome"
    const val ROOM_ORIGIN = "https://luvly-44c77-room-ar.web.app"
    fun webXr(modelId: String): String {
        require(modelId == "princess-wedding")
        return "$ROOM_ORIGIN/?model=princess-wedding"
    }
    // Kept as an explicitly separate legacy integration. The app uses WebXR
    // because current Google app Scene Viewer versions can crash on launch.
    const val PACKAGE = "com.google.ar.core"
    fun sceneViewer(download: String): String {
        val uri = URI(download)
        require(uri.scheme == "https" && uri.host == "firebasestorage.googleapis.com" &&
            uri.port == -1 && uri.userInfo == null && uri.fragment == null)
        require(uri.rawPath.matches(Regex("/v0/b/luvly-44c77\\.firebasestorage\\.app/o/ar-models%2[Ff]princess-room-[0-9a-f]{16}\\.glb")))
        require(uri.rawQuery?.matches(Regex("alt=media&token=[0-9a-f-]{36}")) == true)
        val encoded = URLEncoder.encode(download, "UTF-8")
        return "https://arvr.google.com/scene-viewer/1.0?file=$encoded&mode=ar_only" +
            "&title=Princess%20Wedding%20Dress&resizable=true"
    }
}
