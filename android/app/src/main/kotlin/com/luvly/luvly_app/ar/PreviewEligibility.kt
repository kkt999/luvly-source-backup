package com.luvly.luvly_app.ar

/** The button is available once the camera session has delivered its first frame.
 * The latest frame and pose are checked separately when taking the photo. */
object PreviewEligibility {
    fun canPress(active: Boolean, modelLoaded: Boolean, cameraStarted: Boolean,
                 frozen: Boolean, countingDown: Boolean, saving: Boolean): Boolean =
        active && !saving && (frozen || countingDown || (modelLoaded && cameraStarted))
}
