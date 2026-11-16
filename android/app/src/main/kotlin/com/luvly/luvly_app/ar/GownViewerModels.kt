package com.luvly.luvly_app.ar

/** Text and capabilities for local orbit views; assets still use the shared allowlist. */
data class GownViewerInfo(val title: String, val about: String, val roomAvailable: Boolean=false,
                          val initialZoom: Double=1.45)

object GownViewerModels {
    fun info(dress: ArDress): GownViewerInfo? {
        if(ArDressCatalogue.resolve(dress.id,dress.asset)==null)return null
        return when(dress.id) {
            "princess-wedding" -> GownViewerInfo("Princess Wedding Dress",
                "Princess Wedding Dress by Messrs\nCC BY 4.0\n\nAdapted geometry, materials and morphs for Luvly. This is a visual reference, not a size guide.\n\nSource: https://sketchfab.com/3d-models/clothesdress-princess-wedding-dress-0c06a70e6e694660aeb695df418751cb\nLicense: https://creativecommons.org/licenses/by/4.0/",true)
            "francine-reference" -> GownViewerInfo("Francine Gown",
                "Independent approximate reconstruction referencing Rebecca Ingram Francine (23RB645). No manufacturer affiliation.\n\nExplore the folded neckline, fitted silhouette and covered back buttons. This is a visual reference, not an official manufacturer model or a size guide.\n\nReference: https://www.maggiesottero.com/rebecca-ingram/francine/18883")
            "elegant-local-review" -> GownViewerInfo("Elegant Bridal Gown",
                "Elegant Bridal Gown by Fashionart3d, TurboSquid 2434090. Standard License. Adapted materials and 1K textures.\n\nLocal Android debug preview only. Redistribution of this 3D asset remains restricted. This is a visual reference, not a size guide.\n\nSource: https://www.turbosquid.com/3d-models/2434090",initialZoom=1.85)
            else -> null
        }
    }
}
