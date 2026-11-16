package com.luvly.luvly_app.ar

import kotlin.math.*

/** Bounded lower-skirt shear towards screen-down for an upright camera.
 * The bodice still follows the registered torso. This is a visual deformation,
 * not measured gravity, a fitted body surface, or cloth/contact simulation.
 * Two model targets have displacement .6 * integratedSmoothDrop(y), in X/Z.
 */
object SkirtDrape {
    const val TARGET_SCALE = .6f
    fun weights(matrix: FloatArray): FloatArray {
        if(matrix.size!=16 || matrix.any { !it.isFinite() })return floatArrayOf(0f,0f)
        val height=sqrt(matrix[4]*matrix[4]+matrix[5]*matrix[5])
        val width=sqrt(matrix[0]*matrix[0]+matrix[1]*matrix[1]+matrix[2]*matrix[2])
        val depth=sqrt(matrix[8]*matrix[8]+matrix[9]*matrix[9]+matrix[10]*matrix[10])
        if(minOf(height,width,depth)<1e-3f || matrix[5]<=0)return floatArrayOf(0f,0f)
        // Large bends are outside this simple model. Saturate the correction
        // rather than amplifying it or abruptly switching it off mid-movement.
        val roll=atan2(-matrix[4],matrix[5]).coerceIn(-.30f,.30f)
        val yaw=atan2(-matrix[2],hypot(matrix[0],matrix[1]))
        // At yaw >90 degrees the projected local X changes sign.
        val cy=if(matrix[0]<0f)-cos(yaw) else cos(yaw)
        val sy=sin(yaw)
        val correction=-tan(roll)*height*.70f/TARGET_SCALE
        val x=correction*cy/width
        val z=correction*sy/depth
        // Preserve direction under abnormal scale ratios instead of clipping
        // each axis separately (which would introduce depth motion on turns).
        val divisor=max(1f,max(abs(x),abs(z)))
        return floatArrayOf(x/divisor,z/divisor)
    }
}
