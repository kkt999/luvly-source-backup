package com.luvly.luvly_app.ar

import kotlin.math.*

/** Lightweight foreground-arm colour matte, not semantic skin segmentation.
 * Learns colour from each current-frame limb; no fixed skin-tone thresholds.
 * Requires reliable foreground geometry, consistent seeds and contrasting edges.
 * Never reuses camera pixels/masks. Ambiguous uniform regions remain covered. */
object FastArmMask {
    fun pixels(rgb: IntArray,w: Int,h: Int,points: List<BodyPoint>,sourceW:Int=w,sourceH:Int=h): IntArray? {
        if(w<=0 || h<=0 || rgb.size!=w*h)return null
        if(sourceW<=0 || sourceH<=0)return null
        val sx=w.toFloat()/sourceW;val sy=h.toFloat()/sourceH
        val capsules=ArmOcclusion.capsules(points,sourceW,sourceH,2.5f,skinIntersection=true).map {
            ArmCapsule(it.ax*sx,it.ay*sy,it.bx*sx,it.by*sy,it.startRadius*min(sx,sy),it.endRadius*min(sx,sy)) }
        if(capsules.isEmpty())return null
        val out=IntArray(w*h)
        fun colour(p:Int): FloatArray {
            val r=((p ushr 16) and 255).toFloat();val g=((p ushr 8) and 255).toFloat();val b=(p and 255).toFloat()
            return floatArrayOf(.299f*r+.587f*g+.114f*b,-.169f*r-.331f*g+.5f*b,.5f*r-.419f*g-.081f*b)
        }
        fun sample(x:Float,y:Float):FloatArray? {
            if(x<0 || x>=w || y<0 || y>=h)return null
            return colour(rgb[y.toInt()*w+x.toInt()])
        }
        fun distance(a:FloatArray,b:FloatArray)=sqrt((a[0]-b[0]).pow(2)*.25f+(a[1]-b[1]).pow(2)+(a[2]-b[2]).pow(2))
        for(c in capsules) {
            val dx=c.bx-c.ax;val dy=c.by-c.ay;val length=hypot(dx,dy)
            if(length<5)continue
            val nx=-dy/length;val ny=dx/length
            val seeds=mutableListOf<FloatArray>();val outside=mutableListOf<FloatArray>()
            for(i in 1..7) {
                val t=i/8f;val x=c.ax+dx*t;val y=c.ay+dy*t;val r=c.startRadius+(c.endRadius-c.startRadius)*t
                for(sign in listOf(-.2f,0f,.2f))sample(x+nx*r*sign,y+ny*r*sign)?.let { seeds.add(it) }
                for(sign in listOf(-1.8f,1.8f))sample(x+nx*r*sign,y+ny*r*sign)?.let { outside.add(it) }
            }
            if(seeds.size<12 || outside.size<6)continue
            val median=FloatArray(3) { channel->seeds.map { it[channel] }.sorted()[seeds.size/2] }
            val spread=seeds.map { distance(it,median) }.sorted()[seeds.size/2]
            val edge=outside.map { distance(it,median) }.sorted()[outside.size/2]
            if(spread>16 || edge<14 || median[0]<18 || median[0]>240)continue
            val radius=max(c.startRadius,c.endRadius)
            val x0=floor(min(c.ax,c.bx)-radius).toInt().coerceAtLeast(0)
            val x1=ceil(max(c.ax,c.bx)+radius).toInt().coerceAtMost(w-1)
            val y0=floor(min(c.ay,c.by)-radius).toInt().coerceAtLeast(0)
            val y1=ceil(max(c.ay,c.by)+radius).toInt().coerceAtMost(h-1)
            for(y in y0..y1)for(x in x0..x1) {
                val t=(((x+.5f-c.ax)*dx+(y+.5f-c.ay)*dy)/(length*length)).coerceIn(0f,1f)
                val r=c.startRadius+(c.endRadius-c.startRadius)*t
                val geometric=((r-hypot(x+.5f-c.ax-t*dx,y+.5f-c.ay-t*dy))/max(1f,r*.15f)).coerceIn(0f,1f)
                if(geometric<=0)continue
                val similarity=((24f-distance(colour(rgb[y*w+x]),median))/10f).coerceIn(0f,1f)
                val alpha=(255*geometric*similarity).roundToInt()
                if(alpha>(out[y*w+x] ushr 24))out[y*w+x]=(alpha shl 24) or 0xffffff
            }
        }
        return out.takeIf { it.any { pixel->pixel ushr 24>0 } }
    }
}
