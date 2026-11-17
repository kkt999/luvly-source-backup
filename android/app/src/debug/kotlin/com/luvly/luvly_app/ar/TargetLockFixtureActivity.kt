package com.luvly.luvly_app.ar

import android.graphics.*
import android.os.*
import java.io.File
import kotlin.math.*

/** Camera-free two-body fixture. Exercises selection AND the real display path. */
class TargetLockFixtureActivity: TryOnActivity() {
    private val handler=Handler(Looper.getMainLooper())
    private val lock=BodyTargetLock()
    private var alive=true
    private data class Stage(val name: String,val yaw: Float=0f,val reversed: Boolean=false,
                             val occluded: Boolean=false,val missing: Boolean=false,val ambiguous: Boolean=false,
                             val visible: Boolean=true,val briefLoss: Boolean=false,
                             val singleBody: Boolean=false,val closeCrop: Boolean=false)
    private val stages=listOf(Stage("central-acquisition"),Stage("detector-order-reversed",reversed=true),
        Stage("profile",yaw=75f),Stage("brief-profile-recovery",yaw=75f,briefLoss=true),
        Stage("arm-occlusion",occluded=true,visible=false),
        Stage("front-recovery",reversed=true),Stage("only-reflection",missing=true,visible=false),
        Stage("same-position-return"),Stage("ambiguous-overlap",ambiguous=true,visible=false),
        Stage("ambiguity-cleared"),Stage("back-view",yaw=120f,visible=false),
        Stage("front-before-distance-change",singleBody=true),
        Stage("close-upper-body-recovery",singleBody=true,closeCrop=true),
        Stage("full-body-recovery",singleBody=true))
    private val samples=linkedMapOf<String,MutableList<Boolean>>()
    override fun onCreate(savedInstanceState: Bundle?) {
        val dress=ArDressCatalogue.byId("princess-wedding")!!
        intent.putExtra("dressId",dress.id);intent.putExtra("modelAsset",dress.asset)
        super.onCreate(savedInstanceState)
    }
    override fun beginCameraExperience() {
        val frame=FrameProjection(600,900,800f,800f,source="synthetic-two-body-targets")
        val projection=frame.forView(600,900)!!
        data class Person(val points: List<BodyPoint>,val world: List<WorldBodyPoint>)
        fun person(offset: Float,yaw: Float=0f,occluded: Boolean=false,closeCrop: Boolean=false): Person {
            val source=MutableList(33){Vec3(0f,0f,0f)}
            source[0]=Vec3(0f,.75f,0f)
            source[2]=Vec3(-.04f,.78f,0f);source[5]=Vec3(.04f,.78f,0f)
            source[11]=Vec3(-.2f,.52f,0f);source[12]=Vec3(.2f,.52f,0f)
            source[23]=Vec3(-.14f,0f,0f);source[24]=Vec3(.14f,0f,0f)
            val a=Math.toRadians(yaw.toDouble()).toFloat()
            val world=source.map { Vec3(it.x*cos(a),it.y,-it.x*sin(a)) }
            val translation=if(closeCrop)Vec3(offset,-.65f,-1.1f) else Vec3(offset,0f,-2.5f)
            val points=world.mapIndexed { i,p->
                val xy=projection.project(p+translation)!!
                BodyPoint(xy.first/600,1-xy.second/900,if(occluded && i in listOf(11,12)).2f else 1f)
            }
            return Person(points,world.map { WorldBodyPoint(it.x,-it.y,-it.z,1f) })
        }
        var start=0L
        handler.post(object: Runnable {
            override fun run() {
                if(!alive)return
                if(!window.decorView.hasWindowFocus()) { handler.postDelayed(this,200);return }
                val now=SystemClock.uptimeMillis();if(start==0L)start=now
                val elapsed=now-start;val index=(elapsed/3000).toInt()
                if(index>=stages.size) {
                    File(filesDir,"ar_target_lock_result.txt").writeText(buildString {
                        appendLine("Completed: ${System.currentTimeMillis()} · Build ${com.luvly.luvly_app.BuildConfig.VERSION_CODE}")
                        appendLine("Synthetic two-body inputs; no camera or identity-recognition claim")
                        stages.forEach { s->val v=samples[s.name].orEmpty()
                            appendLine("${if(v.size>=3 && v.all { it })"PASS" else "FAIL"} ${s.name}: samples=${v.size}") }
                    })
                    return
                }
                val s=stages[index]
                val actual=person(.08f,s.yaw,s.occluded || (s.briefLoss && elapsed%3000<800),s.closeCrop)
                val reflection=person(-.62f)
                val people=when {
                    s.singleBody -> listOf(actual)
                    s.missing -> listOf(reflection)
                    s.ambiguous -> listOf(actual,person(.12f))
                    s.reversed -> listOf(actual,reflection)
                    else -> listOf(reflection,actual)
                }
                val selected=lock.select(people.map { it.points },600,900,now)
                val chosen=selected.index?.let { people[it] }
                val bitmap=Bitmap.createBitmap(600,900,Bitmap.Config.ARGB_8888)
                val canvas=Canvas(bitmap);canvas.drawColor(Color.rgb(228,231,235))
                val paint=Paint(Paint.ANTI_ALIAS_FLAG)
                people.forEachIndexed { i,p->
                    paint.color=if(p===actual)Color.rgb(55,125,132) else Color.rgb(150,150,160)
                    val path=Path()
                    for((j,k) in listOf(11,12,24,23).withIndex()) {
                        val q=p.points[k];if(j==0)path.moveTo(q.x*600,q.y*900) else path.lineTo(q.x*600,q.y*900)
                    }
                    path.close();canvas.drawPath(path,paint)
                    val head=p.points[0];canvas.drawCircle(head.x*600,head.y*900,28f,paint)
                    paint.textSize=18f;canvas.drawText("Candidate $i",head.x*600-50,head.y*900-40,paint)
                }
                paint.color=Color.DKGRAY;paint.textSize=18f;canvas.drawText(s.name,30f,40f,paint)
                displayCameraFrame(bitmap,chosen?.points ?: emptyList(),now-100,world=chosen?.world ?: emptyList(),
                    projection=frame,targetReason=selected.reason,resetAlignment=selected.resetAlignment,
                    detectedPeople=people.size,targetIndex=selected.index,retainCalibration=selected.retainCalibration)
                val sampleAt=if(s.singleBody)2200 else 1800
                if(elapsed%3000>=sampleAt) {
                    val p=spatialPoseProbe();val display=trackingDisplayProbe()
                    val valid=when {
                        !s.visible -> p==null && !display.first && !display.third
                        p==null || !display.first -> false
                        s.closeCrop -> p.registrationMode==UpperBodyPreview.MODE
                        else -> p.registrationMode!=UpperBodyPreview.MODE && abs(p.shoulder.x-.08f)<.03f
                    }
                    samples.getOrPut(s.name){mutableListOf()}.add(valid)
                }
                handler.postDelayed(this,200)
            }
        })
    }
    override fun onDestroy() { alive=false;handler.removeCallbacksAndMessages(null);super.onDestroy() }
}
