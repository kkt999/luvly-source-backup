package com.luvly.luvly_app.makeup

import android.content.Intent
import android.os.SystemClock
import android.test.InstrumentationTestCase
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Loads the actual bundled renderer in Android WebView. Never starts a camera. */
@Suppress("DEPRECATION")
class BridalMakeupDeviceTest : InstrumentationTestCase() {
    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) {
            findWebView(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    fun testBundledSdkImportsThroughTheRealAssetOriginWithoutCameraAccess() {
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, BridalMakeupActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        try {
            var web: WebView? = null
            instrumentation.runOnMainSync { web = findWebView(activity.window.decorView) }
            assertNotNull(web)
            val deadline = SystemClock.elapsedRealtime() + 30000
            var result = ""
            while (SystemClock.elapsedRealtime() < deadline) {
                val latch = CountDownLatch(1)
                instrumentation.runOnMainSync {
                    web!!.evaluateJavascript("""
                        (() => {
                          if (document.getElementById('start') && !window.__makeupImportCheck) {
                            window.__makeupImportCheck = 'loading';
                            import('./sdk/index.js').then(module => {
                              window.__makeupImportCheck = typeof module.OpenMakeup === 'function' ? 'ready' : 'missing-export';
                            }).catch(() => { window.__makeupImportCheck = 'import-failed'; });
                          }
                          return window.__makeupImportCheck || 'waiting-page';
                        })()
                    """.trimIndent()) { value -> result = value; latch.countDown() }
                }
                assertTrue("WebView did not respond", latch.await(5, TimeUnit.SECONDS))
                if (result == "\"ready\"" || result == "\"import-failed\"" || result == "\"missing-export\"") break
                SystemClock.sleep(100)
            }
            assertEquals("Bundled SDK should import without a missing renderer module", "\"ready\"", result)
        } finally {
            instrumentation.runOnMainSync { activity.finish() }
        }
    }
}
