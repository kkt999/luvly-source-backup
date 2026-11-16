package com.luvly.luvly_app.ar

import java.io.File
import kotlin.math.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Evaluation only: learned world coordinates are NOT assumed to be ground truth.
 * Private replay inputs are optional local files and never packaged in the app. */
class BodyScanMethodEvaluationTest {
    private data class Point(val x: Double,val y: Double,val z: Double)
    private fun distance(a: Point,b: Point)=sqrt((a.x-b.x).pow(2)+(a.y-b.y).pow(2)+(a.z-b.z).pow(2))
    private fun mid(a: Point,b: Point)=Point((a.x+b.x)/2,(a.y+b.y)/2,(a.z+b.z)/2)
    private fun ratios(p: List<Point>): List<Double> {
        val s=distance(p[0],p[1]);val h=distance(p[2],p[3])
        return listOf(s/h,distance(mid(p[0],p[1]),mid(p[2],p[3]))/s)
    }
    private fun median(v: List<Double>): Double {val s=v.sorted();return if(s.size%2==0)(s[s.size/2-1]+s[s.size/2])/2 else s[s.size/2]}
    private fun spread(v: List<Double>): Double {val m=median(v);return median(v.map{abs(it-m)})/m*100}

    @Test fun perfectWorldGeometryIsRotationInvariantButProjectionIsNot() {
        val p=listOf(Point(-.2,-.5,0.0),Point(.2,-.5,0.0),Point(-.15,0.0,0.0),Point(.15,0.0,0.0))
        val angle=Math.toRadians(25.0)
        // Rotation about horizontal camera axis plus perspective at 2m.
        val turned=p.map{Point(it.x,it.y*cos(angle)-it.z*sin(angle),it.y*sin(angle)+it.z*cos(angle))}
        val original=ratios(p);val world=ratios(turned)
        for(i in 0..1)assertEquals(original[i],world[i],1e-9)
        fun project(points: List<Point>)=points.map{Point(it.x/(2+it.z),it.y/(2+it.z),0.0)}
        val projected=ratios(project(turned));val front=ratios(project(p))
        assertTrue("Perspective changes apparent shoulder/hip ratio",abs(projected[0]/front[0]-1)>.05)
        // This proves the geometry only; estimated world coordinates can be biased.
    }

    @Test fun compareMethodsOnTheSameAcceptedReplayWindows() {
        val supplied=System.getenv("LUVLY_SCAN_EVAL_REPLAYS")
        assumeTrue("No private replays supplied",!supplied.isNullOrBlank())
        fun people(raw: String): List<List<BodyProportionScan.Joint>> = if(raw.isEmpty())emptyList() else raw.split('/').map{person->person.split(';').map{point->
            val v=point.split(',').map{it.toDouble()};BodyProportionScan.Joint(v[0],v[1],v[2],v[3])
        }}
        var totalWindows=0
        for((index,path)in supplied!!.split(';').withIndex()) {
            val file=File(path);assertTrue(file.isFile)
            val scan=BodyProportionScan();val history=mutableListOf<List<Double>>()
            var windows=0
            file.forEachLine{line->
                val c=line.split('\t');val p=people(c[1]);val w=people(c[2])
                val u=scan.add(p,w,480,640,c[0].toLong(),120.0)
                if(u.count==0)history.clear()
                else if(u.guidance in listOf("Hold still while we check your proportions","Keep still; refining your scan","Scan ready to review")) {
                    val ids=listOf(11,12,23,24)
                    val image=ratios(ids.map{Point(p[0][it].x*480,p[0][it].y*640,0.0)})
                    val world=ratios(ids.map{Point(w[0][it].x,w[0][it].y,w[0][it].z)})
                    assertTrue((image+world).all{it.isFinite() && it>0})
                    history.add(image+world)
                    while(history.size>u.count)history.removeAt(0)
                }
                if(u.result!=null) {
                    assertEquals(u.count,history.size)
                    val m=(0..3).map{column->spread(history.map{it[column]})}
                    println("Method evaluation clip=${index+1} window=${++windows} samples=${history.size} relativeMADPercent imageSH=${m[0]} imageTS=${m[1]} worldSH=${m[2]} worldTS=${m[3]}; NOT accuracy")
                    scan.reset();history.clear()
                }
            }
            totalWindows+=windows
            if(windows==0)println("Method evaluation clip=${index+1}: no accepted window in desktop re-inference; no method comparison available")
        }
        assertTrue("Need at least one accepted window to compare methods",totalWindows>0)
    }
}
