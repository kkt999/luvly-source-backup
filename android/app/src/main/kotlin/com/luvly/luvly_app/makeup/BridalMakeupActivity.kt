package com.luvly.luvly_app.makeup

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.util.AndroidRuntimeException
import android.view.ViewGroup
import android.webkit.PermissionRequest
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import java.io.IOException

class BridalMakeupActivity : ComponentActivity() {
    private var mirror: WebView? = null
    private var pendingCamera: PermissionRequest? = null
    private val requestCamera = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        val request = pendingCamera ?: return@registerForActivityResult
        pendingCamera = null
        if (allowed && !isFinishing) request.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
        else request.deny()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
        val cream = Color.rgb(250, 246, 242)
        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(cream)
            ViewCompat.setOnApplyWindowInsetsListener(this) { view, insets ->
                val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
                insets
            }
        }
        page.addView(Button(this, null, android.R.attr.borderlessButtonStyle).apply {
            text = "‹ Gown details"
            isAllCaps = false
            setTextColor(Color.rgb(120, 54, 72))
            setOnClickListener { finish() }
        }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        setContentView(page)
        ViewCompat.requestApplyInsets(page)

        val web = try {
            WebView(this)
        } catch (_: AndroidRuntimeException) {
            page.addView(TextView(this).apply {
                text = "Update Android System WebView to open the makeup preview."
            })
            return
        }
        mirror = web
        web.setBackgroundColor(cream)
        web.settings.apply {
            javaScriptEnabled = true
            allowFileAccess = false
            allowContentAccess = false
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                request.url.toString() != START_URL

            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse =
                localAsset(request)
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onPermissionRequest(request: PermissionRequest) {
                if (!isLocalOrigin(request.origin) ||
                    !request.resources.contentEquals(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE)) ||
                    isFinishing || pendingCamera != null
                ) {
                    request.deny()
                } else if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                    request.grant(arrayOf(PermissionRequest.RESOURCE_VIDEO_CAPTURE))
                } else {
                    pendingCamera = request
                    requestCamera.launch(Manifest.permission.CAMERA)
                }
            }

            override fun onPermissionRequestCanceled(request: PermissionRequest) {
                if (pendingCamera === request) pendingCamera = null
            }
        }
        page.addView(web, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        web.loadUrl(START_URL)
    }

    override fun onStop() {
        mirror?.evaluateJavascript("window.dispatchEvent(new Event('pagehide'))", null)
        super.onStop()
    }

    override fun onDestroy() {
        pendingCamera?.deny()
        pendingCamera = null
        mirror?.let { web ->
            (web.parent as? ViewGroup)?.removeView(web)
            web.destroy()
        }
        mirror = null
        super.onDestroy()
    }

    private fun localAsset(request: WebResourceRequest): WebResourceResponse {
        val path = request.url.path.orEmpty()
        if (request.method != "GET" || !isLocalOrigin(request.url) || !path.startsWith(ASSET_PATH)) {
            return missing()
        }
        val relative = path.removePrefix(ASSET_PATH)
        if (relative.split('/').any { it.isEmpty() || it == "." || it == ".." || '\\' in it }) return missing()
        val mime = when (relative.substringAfterLast('.').lowercase()) {
            "html" -> "text/html"
            "css" -> "text/css"
            "js" -> "text/javascript"
            "json" -> "application/json"
            "glsl" -> "text/plain"
            "glb" -> "model/gltf-binary"
            "png" -> "image/png"
            "wasm" -> "application/wasm"
            else -> "application/octet-stream"
        }
        val encoding = if (mime.startsWith("text/") || mime == "application/json") "UTF-8" else null
        return try {
            WebResourceResponse(mime, encoding, 200, "OK", HEADERS, assets.open("makeup/$relative"))
        } catch (_: IOException) {
            missing()
        }
    }

    private fun missing() =
        WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", emptyMap(), null)

    private fun isLocalOrigin(uri: Uri) = uri.scheme == "https" && uri.authority == HOST

    companion object {
        private const val HOST = "appassets.androidplatform.net"
        private const val ASSET_PATH = "/makeup/"
        private const val START_URL = "https://$HOST${ASSET_PATH}index.html"
        private val HEADERS = mapOf(
            // The bundled FaceMesh runtime uses new Function. Other origins cannot load here.
            "Content-Security-Policy" to "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' blob: data:; worker-src 'self' blob:; object-src 'none'; frame-ancestors 'none'",
            "Permissions-Policy" to "camera=(self), microphone=()",
            "X-Content-Type-Options" to "nosniff",
        )
    }
}
