package com.luvly.luvly_app.ar
import org.junit.Assert.*
import org.junit.Test

class GownViewerModelsTest {
    @Test fun eachApprovedModelKeepsItsOwnTitleAndCredits() {
        val titles=mapOf("princess-wedding" to "Princess Wedding Dress",
            "francine-reference" to "Francine Gown","elegant-local-review" to "Elegant Bridal Gown")
        for((id,title) in titles){
            val dress=ArDressCatalogue.byId(id)!!
            val info=GownViewerModels.info(dress)!!
            assertEquals(title,info.title)
            assertTrue(info.about.contains("https://"))
            assertEquals(id=="princess-wedding",info.roomAvailable)
        }
        assertTrue(GownViewerModels.info(ArDressCatalogue.byId("elegant-local-review")!!)!!.about.contains("Local Android debug preview only"))
    }
    @Test fun forgedModelAndAssetPairsCannotOpenOrbitView() {
        assertNull(GownViewerModels.info(ArDress("francine-reference","assets/models/princess_wedding.glb","Spoof")))
        assertNull(GownViewerModels.info(ArDress("unknown","assets/models/francine_reference.glb","Spoof")))
    }
}
