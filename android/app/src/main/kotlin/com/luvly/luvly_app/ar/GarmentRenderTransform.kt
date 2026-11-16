package com.luvly.luvly_app.ar

import kotlin.math.*

/** Body-aligned weak-perspective rendering of the actual 3D mesh.
 *
 * Monocular world joints are not a calibrated camera/body reconstruction. Applying
 * full-screen perspective to long authored trains magnified errors in pitch and
 * depth: below-centre people acquired raised trains and hollow-looking necklines.
 * Use measured image shoulder/hip anchors for placement and scale, and filtered
 * world yaw for true mesh rotation/depth testing. Upright gowns deliberately do
 * not follow uncertain whole-body pitch. This is not cloth simulation or SLAM.
 */
object GarmentRenderTransform {
    fun matrix(pose: DressPose,anchors: DressAnchors,adjustment: Float=1f): FloatArray {
        val limit=if(pose.unprojectedWidth)92f else 50f
        val yaw=Math.toRadians((pose.spatial?.yawDegrees ?: 0f).coerceIn(-limit,limit).toDouble()).toFloat()
        val cy=cos(yaw);val sy=sin(yaw)
        val cr=cos(pose.roll);val sr=sin(pose.roll)
        // Image shoulder span already contains turn foreshortening. Undo it once
        // before rotating the 3D mesh so the garment is not narrowed twice.
        val bodyWidth=if(pose.unprojectedWidth)pose.widthScale else pose.widthScale/cy
        val width=bodyWidth*adjustment
        val depth=bodyWidth
        val x=Vec3(cr*cy*width,sr*cy*width,-sy*width)
        val y=Vec3(-sr*pose.heightScale,cr*pose.heightScale,0f)
        val z=Vec3(cr*sy*depth,sr*sy*depth,cy*depth)
        // Imported models have different authored body-depth origins. Rotate
        // about the wearer, never about the centre of the train/bounding box.
        val t=Vec3(pose.x,pose.y,0f)-y*anchors.shoulderY-z*anchors.bodyZ
        return floatArrayOf(x.x,x.y,x.z,0f,y.x,y.y,y.z,0f,z.x,z.y,z.z,0f,t.x,t.y,t.z,1f)
    }
}
