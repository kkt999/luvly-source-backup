package com.luvly.luvly_app.ar

import android.view.Surface
import android.view.TextureView
import com.google.android.filament.*
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.*
import java.nio.ByteBuffer
import kotlin.math.sqrt
import kotlin.math.sin
import kotlin.math.cos

/** Separate engine/scene: does not change live try-on materials, morphs or camera. */
class GownViewerRenderer(texture: TextureView, initialZoom: Double=1.45) {
    private val engine: Engine
    private val renderer: Renderer
    private val scene: Scene
    private val view: com.google.android.filament.View
    private val camera: Camera
    private val provider: UbershaderProvider
    private val loader: AssetLoader
    private val resources: ResourceLoader
    private val light: Int
    private val fill: IndirectLight
    private val grading: ColorGrading
    private val helper=UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
    private var swap: SwapChain?=null
    private var asset: FilamentAsset?=null
    private var entities=IntArray(0)
    private var center=floatArrayOf(0f,0f,0f)
    private var radius=1.0
    private var aspect=1.0
    private var closed=false
    val orbit=GownOrbit(initialZoom)
    init {
        Filament.init(); Gltfio.init()
        engine=Engine.create()
        renderer=engine.createRenderer()
        scene=engine.createScene()
        camera=engine.createCamera(EntityManager.get().create())
        camera.setExposure(16f,1f/125f,100f)
        view=engine.createView().apply { this.scene=this@GownViewerRenderer.scene; this.camera=this@GownViewerRenderer.camera }
        view.blendMode=com.google.android.filament.View.BlendMode.TRANSLUCENT
        grading=ColorGrading.Builder().toneMapper(ToneMapper.PBRNeutralToneMapper()).build(engine)
        view.colorGrading=grading
        renderer.clearOptions=Renderer.ClearOptions().apply { clear=true; clearColor=floatArrayOf(0f,0f,0f,0f) }
        light=EntityManager.get().create()
        LightManager.Builder(LightManager.Type.DIRECTIONAL).color(1f,1f,1f)
            .intensity(65000f).direction(-.65f,-.45f,-1f).castShadows(false).build(engine,light)
        scene.addEntity(light)
        fill=IndirectLight.Builder().irradiance(1,floatArrayOf(1f,1f,1f)).intensity(22000f).build(engine)
        scene.indirectLight=fill
        provider=UbershaderProvider(engine)
        loader=AssetLoader(engine,provider,EntityManager.get())
        resources=ResourceLoader(engine)
        texture.isOpaque=false; helper.isOpaque=false
        helper.renderCallback=object: UiHelper.RendererCallback {
            override fun onNativeWindowChanged(surface: Surface) {
                swap?.let { engine.destroySwapChain(it) }
                swap=engine.createSwapChain(surface,SwapChainFlags.CONFIG_TRANSPARENT)
            }
            override fun onDetachedFromSurface() {
                swap?.let { engine.destroySwapChain(it) };swap=null;engine.flushAndWait()
            }
            override fun onResized(width: Int,height: Int) {
                val size=RenderViewport.resolve(width,height,texture.width,texture.height) ?: return
                view.viewport=Viewport(0,0,size.first,size.second)
                aspect=size.first.toDouble()/size.second
                updateCamera()
            }
        }
        helper.attachTo(texture)
    }
    fun load(buffer: ByteBuffer) {
        check(!closed && asset==null)
        val loaded=checkNotNull(loader.createAsset(buffer)) { "Invalid model" }
        asset=loaded
        resources.loadResources(loaded)
        // The AR-only torso proxy is not a garment and must never be visible in 360°.
        entities=loaded.entities.filter { loaded.getName(it)!="LuvlyTorsoDepth" }.toIntArray()
        val box=loaded.boundingBox
        center=box.center.copyOf()
        val half=box.halfExtent
        radius=sqrt(half.sumOf { it.toDouble()*it })
        require(radius.isFinite() && radius>0 && center.all { it.isFinite() })
        scene.addEntities(entities)
        loaded.releaseSourceData()
        updateCamera()
    }
    fun updateCamera() {
        if(closed)return
        val eye=orbit.eye(center,radius,aspect)
        // A camera-relative studio key keeps details readable from the rear too.
        val yaw=Math.toRadians(orbit.yaw)
        engine.lightManager.setDirection(engine.lightManager.getInstance(light),
            (-.65*cos(yaw)-sin(yaw)).toFloat(),-.45f,(.65*sin(yaw)-cos(yaw)).toFloat())
        camera.lookAt(eye[0],eye[1],eye[2],center[0].toDouble(),center[1].toDouble(),center[2].toDouble(),0.0,1.0,0.0)
        camera.setProjection(35.0,aspect,radius*.01,radius*100,Camera.Fov.VERTICAL)
    }
    fun render(time: Long) {
        if(closed || asset==null || !helper.isReadyToRender)return
        swap?.let { if(renderer.beginFrame(it,time)){renderer.render(view);renderer.endFrame()} }
    }
    fun close() {
        if(closed)return
        closed=true;helper.detach()
        scene.removeEntities(entities)
        asset?.let { loader.destroyAsset(it) };asset=null
        resources.destroy();loader.destroy();provider.destroyMaterials();provider.destroy()
        scene.indirectLight=null
        engine.destroyEntity(light);EntityManager.get().destroy(light)
        engine.destroyIndirectLight(fill)
        engine.destroyView(view);engine.destroyRenderer(renderer)
        val cameraEntity=camera.entity
        engine.destroyCameraComponent(cameraEntity);EntityManager.get().destroy(cameraEntity)
        engine.destroyColorGrading(grading);engine.destroyScene(scene);engine.destroy()
    }
}
