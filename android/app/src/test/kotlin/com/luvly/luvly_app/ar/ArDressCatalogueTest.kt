package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test
class ArDressCatalogueTest {
    @Test fun pickerHasDistinctLocalPicturesAndHumanReadableStyles() {
        val dresses=ArDressCatalogue.all()
        assertEquals(dresses.size,dresses.map { it.thumbnail }.distinct().size)
        dresses.forEach {
            assertTrue(it.thumbnail.startsWith("assets/images/"))
            assertTrue(it.thumbnail.endsWith(".jpg"))
            assertTrue(it.name.isNotBlank());assertFalse(it.name.contains("•"))
            assertTrue(it.style.isNotBlank())
        }
    }
    @Test fun elegantDebugAssetRequiresExactPair() {
        assertNotNull(ArDressCatalogue.resolve("elegant-local-review", "local_review/elegant_bridal.glb"))
        assertNull(ArDressCatalogue.resolve("elegant-local-review", "assets/models/princess_wedding.glb"))
        assertNull(ArDressCatalogue.resolve("princess-wedding", "local_review/elegant_bridal.glb"))
    }
    @Test fun princessResolvesOnlyItsOwnAsset() {
        assertNotNull(ArDressCatalogue.resolve("princess-wedding", "assets/models/princess_wedding.glb"))
        assertNull(ArDressCatalogue.resolve("princess-wedding", "assets/models/francine_reference.glb"))
        assertNull(ArDressCatalogue.resolve("francine-reference", "assets/models/princess_wedding.glb"))
    }
    @Test fun onlyMatchingKnownDressAndAssetResolve() {
        assertNotNull(ArDressCatalogue.resolve("francine-reference","assets/models/francine_reference.glb"))
        assertNull(ArDressCatalogue.resolve(null,null))
        assertNull(ArDressCatalogue.resolve("golden","assets/models/francine_reference.glb"))
        assertNull(ArDressCatalogue.resolve("francine-reference","assets/models/luvly_aline.glb"))
        assertNull(ArDressCatalogue.resolve("francine-reference","../../other.glb"))
    }
}
