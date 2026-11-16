package com.luvly.luvly_app.ar

/** Starting a hands-free timer must NOT require a body to be in view yet. */
object PreviewEligibility {
    fun canPress(active: Boolean, modelLoaded: Boolean, recentFrame: Boolean,
                 frozen: Boolean, countingDown: Boolean, saving: Boolean): Boolean =
        active && !saving && (frozen || countingDown || (modelLoaded && recentFrame))
}
