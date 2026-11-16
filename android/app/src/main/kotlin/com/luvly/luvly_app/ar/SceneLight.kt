package com.luvly.luvly_app.ar

import kotlin.math.*

/** Bounded camera-brightness harmonization, NOT physical/HDR light estimation.
 * Ignores highly coloured, clipped and near-black pixels. No frames retained. */
internal class SceneLight {
    private var value=1f
    private var last: Long?=null
    fun reset() { value=1f;last=null }
    fun observe(pixels: IntArray,now: Long): Float {
        val previous=last
        if(previous!=null && now<=previous)return value
        val target=estimate(pixels) ?: return value
        val dt=if(previous==null)0f else ((now-previous).coerceAtMost(500))/1000f
        last=now
        // Slow, bounded adaptation avoids flicker from camera auto-exposure.
        val alpha=if(previous==null).12f else 1-exp(-dt/1.2f)
        value+=(target-value)*alpha
        return value
    }
    companion object {
        fun estimate(pixels: IntArray): Float? {
            val neutral=pixels.asSequence().mapNotNull { p->
                val r=((p ushr 16) and 255)/255f;val g=((p ushr 8) and 255)/255f;val b=(p and 255)/255f
                val hi=maxOf(r,g,b);val lo=minOf(r,g,b)
                if(hi-lo>.16f || hi>.97f || lo<.06f)null else .2126f*r+.7152f*g+.0722f*b
            }.sorted().toList()
            if(neutral.size<32)return null
            // Reflectance and illumination are inseparable here: limit the
            // correction rather than treating a dark wall as measured lux.
            return (.72f+.40f*((neutral[neutral.size/2]-.18f)/.55f).coerceIn(0f,1f)).coerceIn(.72f,1.12f)
        }
    }
}
