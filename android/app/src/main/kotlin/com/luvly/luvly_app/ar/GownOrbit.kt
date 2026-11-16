package com.luvly.luvly_app.ar

import kotlin.math.*

/** Product-view camera only; never used for body tracking or fit estimates. */
class GownOrbit(private val initialZoom: Double=1.45) {
    init { require(initialZoom.isFinite() && initialZoom in .75..2.5) }
    var yaw = 0.0; private set
    var pitch = 0.0; private set
    var zoom = initialZoom; private set
    fun reset() { yaw=0.0; pitch=0.0; zoom=initialZoom }
    fun front() { yaw=0.0; pitch=0.0 }
    fun back() { yaw=180.0; pitch=0.0 }
    fun drag(dx: Double, dy: Double) {
        if(!dx.isFinite() || !dy.isFinite()) return
        yaw=((yaw-dx)%360.0+360.0)%360.0
        pitch=(pitch+dy).coerceIn(-30.0,40.0)
    }
    fun scale(factor: Double) {
        if(factor.isFinite() && factor>0) zoom=(zoom*factor).coerceIn(.75,2.5)
    }
    fun eye(center: FloatArray, radius: Double, aspect: Double): DoubleArray {
        require(center.size==3 && center.all { it.isFinite() })
        require(radius.isFinite() && radius>0 && aspect.isFinite() && aspect>0)
        val vertical=Math.toRadians(35.0/2)
        val halfFov=min(vertical,atan(tan(vertical)*aspect))
        val distance=radius/sin(halfFov)*1.08/zoom
        val y=Math.toRadians(yaw); val p=Math.toRadians(pitch)
        return doubleArrayOf(center[0]+distance*sin(y)*cos(p),
            center[1]+distance*sin(p),center[2]+distance*cos(y)*cos(p))
    }
}
