package com.luvly.luvly_app.ar

import kotlin.math.*

/** Body-skin confidence for this exact frame; no masks may be reused on later frames. */
data class SkinConfidence(val width: Int,val height: Int,val values: FloatArray)

object ArmSkinMask {
    fun pixels(skin: SkinConfidence, points: List<BodyPoint>, imageW: Int, imageH: Int): IntArray? {
        if(skin.width<=0 || skin.height<=0 || skin.values.size!=skin.width*skin.height)return null
        // A wider anatomical search area is safe only after intersecting with actual skin edges.
        val capsules=ArmOcclusion.capsules(points,imageW,imageH,2.5f,skinIntersection=true)
        if(capsules.isEmpty())return null
        val pixels=IntArray(skin.values.size)
        for(y in 0 until skin.height) for(x in 0 until skin.width) {
            val index=y*skin.width+x
            val confidence=skin.values[index]
            if(!confidence.isFinite() || confidence<=.6f)continue
            val px=(x+.5f)*imageW/skin.width;val py=(y+.5f)*imageH/skin.height
            var coverage=0f
            for(c in capsules) {
                val dx=c.bx-c.ax;val dy=c.by-c.ay
                val t=(((px-c.ax)*dx+(py-c.ay)*dy)/(dx*dx+dy*dy).coerceAtLeast(1f)).coerceIn(0f,1f)
                val radius=c.startRadius+(c.endRadius-c.startRadius)*t
                val distance=hypot(px-(c.ax+t*dx),py-(c.ay+t*dy))
                coverage=max(coverage,((radius-distance)/max(2f,radius*.2f)).coerceIn(0f,1f))
            }
            val alpha=(255*((confidence-.6f)/.25f).coerceIn(0f,1f)*coverage).roundToInt()
            pixels[index]=(alpha shl 24) or 0x00ffffff
        }
        return pixels
    }
}
