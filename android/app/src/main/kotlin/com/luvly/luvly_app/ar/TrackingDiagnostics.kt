package com.luvly.luvly_app.ar

import java.util.ArrayDeque
import java.util.Locale

/** In-memory operational diagnostics. No frames, coordinates or metrics are uploaded/saved. */
internal class TrackingDiagnostics {
    private data class Sample(val arrival: Long,val age: Long,val accepted: Boolean,val residual: Float?,val reason: String,
                              val mode: String,val timings: FrameTimings?,val perspectiveResidual: Float?)
    private val samples=ArrayDeque<Sample>()
    private val rejected=linkedMapOf<String,Int>()
    fun reset() { samples.clear();rejected.clear() }
    fun observe(arrival: Long,inputTime: Long,accepted: Boolean,residual: Float?,reason: String="unspecified",
                mode: String="perspective",timings: FrameTimings?=null,perspectiveResidual: Float?=null) {
        if(samples.peekLast()?.let { arrival<=it.arrival }==true)reset()
        if(!accepted)rejected[reason]=(rejected[reason] ?: 0)+1
        samples.addLast(Sample(arrival,(arrival-inputTime).coerceAtLeast(0),accepted,
            residual?.takeIf { it.isFinite() && it>=0 },reason,mode,timings,perspectiveResidual))
        while(samples.size>30)samples.removeFirst()
    }
    fun compact(now: Long): String {
        val recent=samples.filter { now-it.arrival in 0..2000 }
        val last=recent.lastOrNull() ?: return "Tracking stats · Waiting for frames\nTap for details"
        if(now-last.arrival>700)return "Tracking paused · Waiting for fresh frames\nTap for details"
        val duration=last.arrival-recent.first().arrival
        val rate=if(duration>0)(recent.size-1)*1000.0/duration else 0.0
        val result=if(last.accepted) "tracked" else last.reason
        return String.format(Locale.US,"%.1f updates/s · %s\n%s · Tap for details",rate,result,
            when(last.mode) { "image-anchored-profile" -> "Profile image fit"; "perspective" -> "Perspective check"; else -> "Reacquiring" })
    }
    fun description(now: Long): String {
        val recent=samples.filter { now-it.arrival in 0..2000 }
        val history=if(rejected.isEmpty())"" else "\nSession interruptions: "+rejected.entries.sortedByDescending { it.value }.take(4).joinToString { "${it.key}: ${it.value}" }
        if(recent.size<2)return "Tracking diagnostics · Waiting for live frames"+history
        val duration=recent.last().arrival-recent.first().arrival
        if(duration<=0)return "Tracking diagnostics · Waiting for live frames"
        val rate=(recent.size-1)*1000.0/duration
        val age=recent.map { it.age }.average().toInt()
        val residuals=recent.filter { it.accepted }.mapNotNull { it.residual }
        val residual=if(residuals.isEmpty())"—" else String.format(Locale.US,"%.1f px",residuals.average())
        val last=recent.last()
        val timings=recent.mapNotNull { it.timings }
        val stages=if(timings.isEmpty())"" else String.format(Locale.US,
            "\nAverage stages: prepare %.0f ms · pose %.0f ms · arms %.0f ms\nArm refinement: %s",
            timings.map { it.preparationMs }.average(),timings.map { it.poseMs }.average(),
            timings.map { it.armsMs }.average(),timings.last().armsMode)+"\nPose processor: ${timings.last().poseBackend} · ${timings.last().poseModel}"
        val mode="\nRegistration: ${last.mode}"+if(last.mode=="image-anchored-profile")
            "\nPerspective residual (not used for rendering): ${last.perspectiveResidual?.toInt() ?: 0} px" else ""
        return String.format(Locale.US,"Tracking updates: %.1f/s · Accepted: %d/%d\nProcessing + display: %d ms · Pose residual: %s\nLatest: %s\nDiagnostics only · Not body measurements",rate,
            recent.count { it.accepted },recent.size,age,residual,if(last.accepted)"tracked" else last.reason)+mode+stages+history
    }
}
