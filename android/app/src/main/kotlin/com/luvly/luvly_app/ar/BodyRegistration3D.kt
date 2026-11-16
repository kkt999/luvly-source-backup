package com.luvly.luvly_app.ar

import kotlin.math.*

/** Camera coordinates: right +X, up +Y, toward viewer +Z; visible points have Z < 0. */
data class Vec3(val x: Float,val y: Float,val z: Float) {
    operator fun plus(b: Vec3)=Vec3(x+b.x,y+b.y,z+b.z)
    operator fun minus(b: Vec3)=Vec3(x-b.x,y-b.y,z-b.z)
    operator fun times(s: Float)=Vec3(x*s,y*s,z*s)
    fun dot(b: Vec3)=x*b.x+y*b.y+z*b.z
    fun cross(b: Vec3)=Vec3(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x)
    fun length()=sqrt(dot(this))
    fun unit(): Vec3? = length().let { if(it.isFinite() && it>1e-5f)this*(1f/it) else null }
    fun finite()=x.isFinite() && y.isFinite() && z.isFinite()
}

/** MediaPipe's hip-relative estimate in metres, NOT a depth-sensor measurement. */
data class WorldBodyPoint(val x: Float,val y: Float,val z: Float,val confidence: Float) {
    fun cameraVector()=Vec3(x,-y,-z)
}

/** Intrinsics for the already-oriented bitmap. Focal metadata/centre crop remain estimates. */
data class FrameProjection(val width: Int,val height: Int,val fx: Float,val fy: Float,
                           val cx: Float=width/2f,val cy: Float=height/2f,
                           val source: String="estimated-fov") {
    fun resized(newWidth: Int,newHeight: Int): FrameProjection {
        require(minOf(width,height,newWidth,newHeight)>0)
        val sx=newWidth.toFloat()/width;val sy=newHeight.toFloat()/height
        return copy(width=newWidth,height=newHeight,fx=fx*sx,fy=fy*sy,cx=cx*sx,cy=cy*sy)
    }
    fun forView(viewW: Int,viewH: Int): PerspectiveProjection? {
        if(minOf(width,height,viewW,viewH)<=0 || !fx.isFinite() || !fy.isFinite() ||
            fx<=0 || fy<=0 || !cx.isFinite() || !cy.isFinite())return null
        val s=min(viewW.toFloat()/width,viewH.toFloat()/height)
        return PerspectiveProjection(viewW,viewH,fx*s,fy*s,
            (viewW-width*s)/2+cx*s,viewH-((viewH-height*s)/2+cy*s),source)
    }
    companion object {
        fun estimated(width: Int,height: Int): FrameProjection {
            val focal=max(width,height)/(2f*tan(Math.toRadians(60.0).toFloat()/2))
            return FrameProjection(width,height,focal,focal)
        }
    }
}

/** Approximate stream projection from physical sensor dimensions, lens and current zoom.
 * CameraX crop/distortion and logical-camera switching are not full calibration.
 */
data class SensorLens(val widthMm: Float,val heightMm: Float,val focalMm: Float) {
    fun frame(rawW: Int,rawH: Int,rotation: Int,zoom: Float): FrameProjection {
        val swap=rotation%180!=0
        val w=if(swap)rawH else rawW;val h=if(swap)rawW else rawH
        if(listOf(widthMm,heightMm,focalMm,zoom).any { !it.isFinite() || it<=0 } || min(rawW,rawH)<=0)
            return FrameProjection.estimated(w,h)
        val focal=focalMm*max(rawW/widthMm,rawH/heightMm)*zoom
        return FrameProjection(w,h,focal,focal,source="lens-metadata-estimate")
    }
}

/** Pixel coordinates use Android's viewport X and bottom-up Y, including FIT_CENTER bars. */
data class PerspectiveProjection(val width: Int,val height: Int,val fx: Float,val fy: Float,
                                 val cx: Float,val cy: Float,val source: String) {
    fun project(p: Vec3): Pair<Float,Float>? {
        if(!p.finite() || p.z>=-.1f)return null
        return Pair(cx+fx*p.x/-p.z,cy+fy*p.y/-p.z)
    }
}

data class SpatialDressPose(val shoulder: Vec3,val right: Vec3,val up: Vec3,
                            val widthScale: Float,val heightScale: Float,
                            val projection: PerspectiveProjection,val errorPixels: Float,
                            val registrationMode: String="perspective",
                            val perspectiveErrorPixels: Float=errorPixels) {
    val forward get()=right.cross(up)
    val yawDegrees get()=Math.toDegrees(atan2(-right.z,right.x).toDouble()).toFloat()
    /** Camera-space diagnostic matrix. Live garments use GarmentRenderTransform:
     * a monocular world fit alone is not sufficient for calibrated lens rendering. */
    fun modelMatrix(shoulderY: Float,adjustment: Float=1f): FloatArray {
        val x=right*(widthScale*adjustment);val y=up*heightScale;val z=forward*widthScale
        val t=shoulder-y*shoulderY
        return floatArrayOf(x.x,x.y,x.z,0f,y.x,y.y,y.z,0f,z.x,z.y,z.z,0f,t.x,t.y,t.z,1f)
    }
    fun transform(local: Vec3,shoulderY: Float): Vec3 =
        shoulder+right*(local.x*widthScale)+up*((local.y-shoulderY)*heightScale)+forward*(local.z*widthScale)
    fun blend(next: SpatialDressPose,positionAlpha: Float,shapeAlpha: Float): SpatialDressPose {
        fun mix(a: Vec3,b: Vec3,t: Float)=a+(b-a)*t
        val r=mix(right,next.right,positionAlpha).unit() ?: next.right
        val rawUp=mix(up,next.up,positionAlpha)
        val u=(rawUp-r*rawUp.dot(r)).unit() ?: next.up
        // Smooth camera-space translation/orientation together. Zoom changes use
        // the newest projection, not a smoothed or stale focal length.
        val center=mix(shoulder,next.shoulder,positionAlpha)
        return next.copy(shoulder=center,right=r,up=u,
            widthScale=widthScale+(next.widthScale-widthScale)*shapeAlpha,
            heightScale=heightScale+(next.heightScale-heightScale)*shapeAlpha)
    }
}

/** Body-relative 3D registration, not SLAM or room anchoring. No synthetic depth if missing. */
object BodyRegistration3D {
    fun register(base: DressPose,points: List<BodyPoint>,world: List<WorldBodyPoint>,
                 imageW: Int,imageH: Int,viewW: Int,viewH: Int,
                 anchors: DressAnchors,frame: FrameProjection,
                 calibratedOrder: Float?=null, profileTolerance: Boolean=false,
                 allowImageAnchoredProfile: Boolean=false,
                 onReject: (String)->Unit={}): DressPose? {
        fun reject(reason: String): DressPose? { onReject(reason);return null }
        if(frame.width!=imageW || frame.height!=imageH || world.size<25 || points.size<25)return reject("missing_world_or_projection")
        val projection=frame.forView(viewW,viewH) ?: return reject("invalid_projection")
        val ids=listOf(11,12,23,24)
        if(ids.any { !world[it].cameraVector().finite() })return reject("invalid_world")
        if(!TorsoVisibility.reliable(ids.map { world[it].confidence },
                calibratedOrder!=null && TorsoVisibility.foreshortened(points,imageW,imageH)))return reject("world_confidence")
        val positions=ids.map { world[it].cameraVector() }
        val shoulder=(positions[0]+positions[1])*.5f
        val hip=(positions[2]+positions[3])*.5f
        // Use image ordering, not anatomical left/right: mirrored front input and
        // rear input have opposite labels but need the same visible garment front.
        if(calibratedOrder!=null && calibratedOrder!=1f && calibratedOrder != -1f)return reject("invalid_order")
        val order=calibratedOrder ?: if(points[12].x>points[11].x)1f else -1f
        val shoulderSpan=(positions[1]-positions[0])*order
        val right=shoulderSpan.unit() ?: return reject("world_geometry")
        val spine=shoulder-hip
        val up=(spine-right*spine.dot(right)).unit() ?: return reject("world_geometry")
        val forward=right.cross(up)
        val torso=spine.dot(up);val shoulderWidth=shoulderSpan.length()
        if(shoulderWidth !in .18f.. .75f || torso !in .20f.. .85f)return reject("world_proportions")
        // A small uncertainty band around profile only applies to an already
        // tracked gradual turn, never initial acquisition or an actual back view.
        val limit=if(calibratedOrder==null)55.0 else if(profileTolerance)100.0 else 92.0
        if(forward.z<cos(Math.toRadians(limit)).toFloat())return reject("turn_limit")
        if(up.y<.65f || abs(up.z)>sin(Math.toRadians(25.0)).toFloat())return reject("torso_tilt")

        val imageScale=min(viewW.toFloat()/imageW,viewH.toFloat()/imageH)
        val dx=(viewW-imageW*imageScale)/2;val dy=(viewH-imageH*imageScale)/2
        val pixels=ids.map { Pair(dx+points[it].x*imageW*imageScale,viewH-dy-points[it].y*imageH*imageScale) }
        val q=pixels.map { Pair((it.first-projection.cx)/projection.fx,(it.second-projection.cy)/projection.fy) }
        // Solve camera translation (Tx,Ty,-D) from world/2D correspondences:
        // Tx = qx*D - (X+qx*Z), Ty = qy*D - (Y+qy*Z).
        val a=positions.indices.map { Pair(positions[it].x+q[it].first*positions[it].z,
            positions[it].y+q[it].second*positions[it].z) }
        val mx=q.map { it.first }.average().toFloat();val my=q.map { it.second }.average().toFloat()
        val ax=a.map { it.first }.average().toFloat();val ay=a.map { it.second }.average().toFloat()
        var numerator=0f;var denominator=0f
        for(i in ids.indices) {
            val x=q[i].first-mx;val y=q[i].second-my
            numerator+=x*(a[i].first-ax)+y*(a[i].second-ay);denominator+=x*x+y*y
        }
        if(denominator<1e-5f)return reject("projection_degenerate")
        val depth=numerator/denominator
        if(!depth.isFinite() || depth !in .5f..8f)return reject("depth_range")
        val translation=Vec3(mx*depth-ax,my*depth-ay,-depth)
        var squaredError=0f
        for(i in ids.indices) {
            val projected=projection.project(positions[i]+translation) ?: return reject("projection_invalid")
            squaredError+=(projected.first-pixels[i].first).pow(2)+(projected.second-pixels[i].second).pow(2)
        }
        val perspectiveError=sqrt(squaredError/ids.size)
        val imageTorso=base.heightScale*(anchors.shoulderY-anchors.hipY)
        var error=perspectiveError
        var center=shoulder+translation
        var mode="perspective"
        if(error>max(8f,imageTorso*.18f)) {
            // Live rendering is image-anchored/weak-perspective already. A depth
            // estimate must not veto a consistent current profile solely because
            // the estimated lens perspective differs. Still require a tight
            // independent all-joint image fit AND a bounded perspective discrepancy.
            if(!allowImageAnchoredProfile || calibratedOrder==null ||
                abs(Math.toDegrees(atan2(-right.z,right.x).toDouble()))<45 ||
                !TorsoVisibility.foreshortened(points,imageW,imageH) ||
                perspectiveError>imageTorso*.35f)return reject("reprojection_error")
            val fit=ProfileImageFit.fit(positions,pixels,imageTorso) ?: return reject("profile_image_mismatch")
            val approximateDepth=(projection.fx+projection.fy)/(2*fit.scale)
            if(approximateDepth !in .5f..8f)return reject("profile_depth_range")
            center=Vec3((base.x-projection.cx)*approximateDepth/projection.fx,
                (base.y-projection.cy)*approximateDepth/projection.fy,-approximateDepth)
            error=fit.error;mode="image-anchored-profile"
        }
        val spatial=SpatialDressPose(center,right,up,shoulderWidth/anchors.shoulderWidth,
            torso/(anchors.shoulderY-anchors.hipY),projection,error,mode,perspectiveError)
        // Use 3D joint separation for the bounded local shape easing. A turn must
        // not narrow the underlying dress mesh a second time after perspective.
        val hipRatio=(positions[3]-positions[2]).length()/shoulderWidth
        var hem=0f
        if(PoseAlignment.fullBodyVisible(points) && world.size>=33 &&
            listOf(31,32).all { world[it].confidence>=.65f && world[it].cameraVector().finite() }) {
            val foot=(world[31].cameraVector()+world[32].cameraVector())*.5f
            val leg=(hip-foot).dot(up);val rest=spatial.heightScale*anchors.hipY
            if(leg/torso in .85f..2.6f && rest>0)hem=((1-leg/rest)/.35f).coerceIn(-.65f,.85f)
        }
        return base.copy(spatial=spatial,hemAdjustment=hem,
            waistFit=if(anchors.adaptiveFit)((hipRatio-.40f)/.45f).coerceIn(.15f,1f) else 0f,
            chestFit=if(anchors.adaptiveFit)((hipRatio-.40f)/.65f).coerceIn(.15f,.65f) else 0f)
    }
}
