package com.luvly.luvly_app.ar

import java.net.URI
import java.net.URLDecoder
import org.junit.Assert.*
import org.junit.Test

class RoomArLinkTest {
    @Test fun roomViewingUsesItsOwnHttpsSiteInChrome() {
        val uri=URI(RoomArLink.webXr("princess-wedding"))
        assertEquals("https",uri.scheme)
        assertEquals("luvly-44c77-room-ar.web.app",uri.host)
        assertEquals("model=princess-wedding",uri.rawQuery)
        assertEquals("com.android.chrome",RoomArLink.BROWSER_PACKAGE)
        assertFalse(uri.host.contains("arvr.google.com"))
    }
    @Test fun roomViewingRejectsUnknownModelsAndUrlInjection() {
        for(id in listOf("francine-reference","https://example.com","princess-wedding&file=secret")) {
            try { RoomArLink.webXr(id);fail("Unexpected model") }
            catch(_:IllegalArgumentException) {}
        }
    }
    private val url="https://firebasestorage.googleapis.com/v0/b/luvly-44c77.firebasestorage.app/o/ar-models%2Fprincess-room-0123456789abcdef.glb?alt=media&token=12345678-abcd-1234-abcd-123456789abc"
    @Test fun packagedModelIsAnAllowedPublicReference() {
        assertTrue(RoomArLink.sceneViewer(RoomModelDownload.URL).contains("mode=ar_only"))
    }
    @Test fun modelUrlSurvivesNestedQueryWithoutLosingItsToken() {
        val result=URI(RoomArLink.sceneViewer(url))
        assertEquals("arvr.google.com",result.host)
        val file=result.rawQuery.split('&').first().substringAfter("file=")
        assertEquals(url,URLDecoder.decode(file,"UTF-8"))
        assertTrue(result.rawQuery.split('&').contains("mode=ar_only"))
        assertEquals("com.google.ar.core",RoomArLink.PACKAGE)
    }
    @Test fun arbitraryHostsAndCustomerMediaCannotBeSentToViewer() {
        val invalid=listOf(url.replace("https:","http:"),url.replace("firebasestorage.googleapis.com","example.com"),
            url.replace("ar-models%2Fprincess-room-","customer-reviews%2Fprincess-room-"),
            url+"&link=https://example.com",url+"#fragment",url.replace(".com/v0", ".com:8443/v0"))
        for(value in invalid) {
            try { RoomArLink.sceneViewer(value);fail("Unexpected accepted URI") }
            catch(_:IllegalArgumentException) {}
        }
    }
}
