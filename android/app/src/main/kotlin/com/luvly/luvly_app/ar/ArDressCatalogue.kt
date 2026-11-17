package com.luvly.luvly_app.ar
import com.luvly.luvly_app.BuildConfig

data class DressAnchors(val shoulderY: Float=1.49f, val hipY: Float=.97f,
                       val shoulderWidth: Float=.40f, val adaptiveFit: Boolean=false,
                       val bodyZ: Float=0f, val torsoOccluderOffsetZ: Float=0f,
                       val lightScale: Float=1f)
data class ArDress(val id: String,val asset: String,val label: String,
                   val anchors: DressAnchors=DressAnchors(),
                   val thumbnail: String="", val style: String="") {
    val name: String get()=label.substringBefore(" •")
}

/** Explicit local allowlist: never fall back to an unrelated gown. */
object ArDressCatalogue {
    private val supported=listOf(ArDress("francine-reference",
        "assets/models/francine_reference.glb","Francine Gown",
        thumbnail="assets/images/francine_reference.jpg",style="Strapless · Fitted silhouette"),
        ArDress("princess-wedding", "assets/models/princess_wedding.glb",
            "Princess • fitted adaptation • Messrs • CC BY 4.0",
            DressAnchors(1.45f,.97f,.40f,true,bodyZ=.53f),
            "assets/images/princess_wedding.jpg","Off-shoulder · Full skirt")) +
        if (BuildConfig.DEBUG) listOf(ArDress("elegant-local-review",
            "local_review/elegant_bridal.glb", "Elegant Bridal • local review • Fashionart3d",
            DressAnchors(1.40f,.97f,.31f,false,bodyZ=.06f),
            "assets/images/elegant_bridal.jpg","High neckline · Long train")) else emptyList()
    fun resolve(id: String?,asset: String?): ArDress? =
        supported.firstOrNull { it.id==id && it.asset==asset }
    fun all(): List<ArDress> = supported.toList()
    fun byId(id: String?): ArDress? = supported.firstOrNull { it.id==id }
}
