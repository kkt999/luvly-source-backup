package com.luvly.luvly_app.ar

import android.content.Context
import com.luvly.luvly_app.BuildConfig
import android.opengl.Matrix
import android.os.SystemClock
import android.view.Surface
import android.view.TextureView
import com.google.android.filament.*
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.*
import java.nio.ByteBuffer

/** Main-thread GLB renderer with body-aligned weak perspective and tracked 3D yaw. */
class DressRenderer(context: Context, texture: TextureView, modelAsset: String,
                    private var anchors: DressAnchors=DressAnchors(),
                    backend: Engine.Backend=Engine.Backend.DEFAULT) {
    private val engine: Engine
    private val renderer: Renderer
    private val scene: Scene
    private val view: com.google.android.filament.View
    private val camera: Camera
    private val provider: UbershaderProvider
    private val loader: AssetLoader
    private var resources: ResourceLoader
    private var asset: FilamentAsset
    private data class PendingDress(val asset: FilamentAsset,val anchors: DressAnchors,
        val startedAt: Long,val completed: (Boolean)->Unit)
    private var pending: PendingDress?=null
    private val helper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
    private var swap: SwapChain? = null
    private val light: Int
    private val ambient: IndirectLight
    private var cameraBrightness=1f
    private val colorGrading: ColorGrading
    private var visible = false
    private var closed = false
    private var viewportWidth=1
    private var viewportHeight=1

    init {
        Filament.init()
        Gltfio.init()
        engine=Engine.create(backend)
        renderer=engine.createRenderer()
        scene=engine.createScene()
        camera=engine.createCamera(EntityManager.get().create())
        camera.lookAt(0.0,0.0,20000.0,0.0,0.0,0.0,0.0,1.0,0.0)
        camera.setExposure(16f,1f/125f,100f)
        view=engine.createView()
        view.scene=scene
        view.camera=camera
        view.blendMode=com.google.android.filament.View.BlendMode.TRANSLUCENT
        // Keep display gamma encoding and highlight compression enabled. Disabling
        // this pipeline sends uncorrected linear lighting to the display.
        colorGrading=ColorGrading.Builder()
            .toneMapper(ToneMapper.PBRNeutralToneMapper())
            .build(engine)
        view.colorGrading=colorGrading
        view.isPostProcessingEnabled=true
        renderer.clearOptions=Renderer.ClearOptions().apply {
            clear=true; clearColor=floatArrayOf(0f,0f,0f,0f)
        }
        light=EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL)
            .color(1f,1f,1f).intensity(32000f).direction(-.65f,-.45f,-1f)
            .castShadows(false).build(engine,light)
        scene.addEntity(light)
        // Neutral diffuse fill keeps curved side surfaces from falling to black.
        // Artistic studio lighting, not an estimate of the camera environment.
        ambient=IndirectLight.Builder()
            .irradiance(1,floatArrayOf(1f,1f,1f))
            .intensity(16000f).build(engine)
        scene.indirectLight=ambient
        updateLighting(cameraBrightness)
        provider=UbershaderProvider(engine)
        loader=AssetLoader(engine,provider,EntityManager.get())
        resources=ResourceLoader(engine)
        val buffer=readModel(context,modelAsset)
        asset=checkNotNull(loader.createAsset(buffer)) { "Dress model could not be loaded" }
        resources.loadResources(asset)
        configureMaterials(asset,anchors)
        asset.releaseSourceData()
        texture.isOpaque=false
        helper.isOpaque=false
        helper.renderCallback=object: UiHelper.RendererCallback {
            override fun onNativeWindowChanged(surface: Surface) {
                swap?.let { engine.destroySwapChain(it) }
                swap=engine.createSwapChain(surface,SwapChainFlags.CONFIG_TRANSPARENT)
            }
            override fun onDetachedFromSurface() {
                swap?.let { engine.destroySwapChain(it) }; swap=null
                engine.flushAndWait()
            }
            override fun onResized(width: Int,height: Int) {
                val size=RenderViewport.resolve(width,height,texture.width,texture.height) ?: return
                viewportWidth=size.first;viewportHeight=size.second
                view.viewport=Viewport(0,0,viewportWidth,viewportHeight)
                configureCamera()
            }
        }
        if(texture.isAvailable && texture.width>0 && texture.height>0)
            helper.setDesiredSize(texture.width,texture.height)
        helper.attachTo(texture)
    }

    companion object {
        /** File IO may run off-thread; all Engine / gltfio calls remain on the main thread. */
        fun readModel(context: Context,modelAsset: String): ByteBuffer {
            if(modelAsset.startsWith("generated-"))return GeneratedDressFile.read(context,modelAsset)
            val assetPath=if(BuildConfig.DEBUG && modelAsset in listOf("local_review/elegant_bridal.glb","local_review/princess_2096.glb"))
                modelAsset else "flutter_assets/$modelAsset"
            val bytes=context.assets.open(assetPath).use { it.readBytes() }
            return ByteBuffer.allocateDirect(bytes.size).apply { put(bytes);flip() }
        }
    }

    private fun configureMaterials(asset: FilamentAsset,modelAnchors: DressAnchors) {
        // The body must hide back-facing wrap fabric. Keep the real camera
        // pixels: this model-space proxy writes depth only, never a skin colour.
        val rm=engine.renderableManager
        for(entity in asset.entities) {
            val instance=rm.getInstance(entity)
            if(instance==0) continue
            val depthOnly=asset.getName(entity)=="LuvlyTorsoDepth"
            if(depthOnly && modelAnchors.torsoOccluderOffsetZ!=0f) {
                // Princess's legacy flat proxy intersected the front bodice.
                // Move only that dedicated identity-transform proxy behind it.
                val transform=FloatArray(16)
                Matrix.setIdentityM(transform,0)
                Matrix.translateM(transform,0,0f,0f,modelAnchors.torsoOccluderOffsetZ)
                val tm=engine.transformManager
                tm.setTransform(tm.getInstance(entity),transform)
            }
            rm.setPriority(instance,if(depthOnly) 0 else 1)
            if(depthOnly) for(i in 0 until rm.getPrimitiveCount(instance)) {
                rm.getMaterialInstanceAt(instance,i).apply {
                    setColorWrite(false); setDepthWrite(true); setDepthCulling(true)
                    setCullingMode(Material.CullingMode.NONE)
                }
            }
        }
    }

    /** Transactional swap: retain the old model until the replacement is fully decoded.
     * Never detach the TextureView or recreate the Engine during a dress change. */
    fun loadDress(buffer: ByteBuffer,nextAnchors: DressAnchors,completed: (Boolean)->Unit) {
        check(!closed && pending==null) { "Renderer is unavailable or already loading" }
        val next=loader.createAsset(buffer)
        if(next==null) { completed(false);return }
        pending=PendingDress(next,nextAnchors,SystemClock.uptimeMillis(),completed)
        try {
            if(!resources.asyncBeginLoad(next))cancelDressLoad(notify=true)
        } catch(_:Exception) { cancelDressLoad(notify=true) }
    }

    fun cancelDressLoad(notify: Boolean=false) {
        val loading=pending ?: return
        pending=null
        resources.asyncCancelLoad()
        resources.evictResourceData()
        loader.destroyAsset(loading.asset)
        // Filament 1.56 can reject the next asyncBeginLoad on some Android GPUs
        // after a cancellation. Recreate only this lightweight loader; keep the
        // Engine, TextureView, old model and camera projection intact.
        resources.destroy()
        if(!closed)resources=ResourceLoader(engine)
        if(notify)loading.completed(false)
    }

    private fun finishDressLoad() {
        val loading=pending ?: return
        try {
            resources.asyncUpdateLoad()
            if(resources.asyncGetLoadProgress()<1f) {
                if(SystemClock.uptimeMillis()-loading.startedAt>20000)cancelDressLoad(notify=true)
                return
            }
            configureMaterials(loading.asset,loading.anchors)
            loading.asset.releaseSourceData()
        } catch(_:Exception) { cancelDressLoad(notify=true);return }
        pending=null
        scene.removeEntities(asset.entities)
        loader.destroyAsset(asset)
        asset=loading.asset;anchors=loading.anchors;visible=false
        updateLighting(cameraBrightness)
        resources.evictResourceData()
        loading.completed(true)
    }

    private fun configureCamera() {
        // Matrix coordinates are viewport pixels. Keep long trains inside the
        // depth range even when the wearer approaches the camera.
        camera.lookAt(0.0,0.0,20000.0,0.0,0.0,0.0,0.0,1.0,0.0)
        camera.setProjection(Camera.Projection.ORTHO,0.0,viewportWidth.toDouble(),0.0,viewportHeight.toDouble(),.1,40000.0)
    }

    fun updateLighting(brightness: Float) {
        if(closed || !brightness.isFinite())return
        cameraBrightness=brightness.coerceIn(.72f,1.12f)
        val intensity=cameraBrightness*anchors.lightScale
        engine.lightManager.setIntensity(engine.lightManager.getInstance(light),32000f*intensity)
        ambient.intensity=16000f*intensity
    }

    fun update(pose: DressPose?, adjustment: Float, skirtDrape: Boolean=true) {
        if (closed) return
        if (pose == null) {
            if (visible) scene.removeEntities(asset.entities)
            visible=false
            return
        }
        // Registration still requires valid world landmarks in live operation;
        // rendering uses its yaw plus image anchors, not an unstable global lens fit.
        val matrix=GarmentRenderTransform.matrix(pose,anchors,adjustment)
        val tm=engine.transformManager
        tm.setTransform(tm.getInstance(asset.root),matrix)
        run {
            val rm=engine.renderableManager
            val weights=floatArrayOf(if(anchors.adaptiveFit)pose.waistFit else 0f,
                if(anchors.adaptiveFit)pose.chestFit else 0f,pose.hemAdjustment)
            for (entity in asset.entities) {
                val instance=rm.getInstance(entity)
                val count=if(instance==0)0 else rm.getMorphTargetCount(instance)
                if(count==3 || (anchors.adaptiveFit && count in listOf(2,4,5,12,14))) {
                    // Princess's fourth target corrects the authored flat bodice,
                    // independent of inferred body proportions and turn angle.
                    val applied=when(count) {
                        12,14 -> weights+floatArrayOf(1f,pose.shoulderTilt.coerceIn(-1f,1f),1f,
                            pose.sleeveLeft.x.coerceIn(-1f,1f),pose.sleeveLeft.y.coerceIn(0f,1f),pose.sleeveLeft.z.coerceIn(-1f,1f),
                            pose.sleeveRight.x.coerceIn(-1f,1f),pose.sleeveRight.y.coerceIn(0f,1f),pose.sleeveRight.z.coerceIn(-1f,1f))+
                            (if(count==14) { if(skirtDrape)SkirtDrape.weights(matrix) else floatArrayOf(0f,0f) } else floatArrayOf())
                        5 -> weights+floatArrayOf(1f,pose.shoulderTilt.coerceIn(-1f,1f))
                        4 -> weights+floatArrayOf(1f); 2 -> weights.copyOf(2); else -> weights }
                    if(count in listOf(12,14) && asset.getName(entity)=="Object_10") {
                        // Upper wrap follows shoulders/arms. Chest/waist expansion
                        // is for the inner bodice and must not inflate cuffs as well.
                        applied[0]=0f;applied[1]=0f
                    }
                    rm.setMorphWeights(instance,applied,0)
                    // Conservative: loader's rest-pose bounds omit fit expansion.
                    rm.setCulling(instance,false)
                }
            }
        }
        if (!visible) scene.addEntities(asset.entities)
        visible=true
    }

    fun render(time: Long) {
        if(closed)return
        finishDressLoad()
        if (closed || !helper.isReadyToRender) return
        swap?.let { if (renderer.beginFrame(it,time)) { renderer.render(view); renderer.endFrame() } }
    }

    fun close() {
        if (closed) return
        closed=true
        cancelDressLoad()
        helper.detach()
        scene.removeEntities(asset.entities)
        loader.destroyAsset(asset)
        loader.destroy()
        provider.destroyMaterials()
        provider.destroy()
        resources.destroy()
        engine.destroyEntity(light)
        EntityManager.get().destroy(light)
        scene.indirectLight=null
        engine.destroyIndirectLight(ambient)
        engine.destroyRenderer(renderer)
        engine.destroyView(view)
        val cameraEntity=camera.entity
        engine.destroyCameraComponent(cameraEntity)
        EntityManager.get().destroy(cameraEntity)
        engine.destroyColorGrading(colorGrading)
        engine.destroyScene(scene)
        engine.destroy()
    }
}
