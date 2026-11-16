package com.luvly.luvly_app.ar

import java.util.ArrayDeque
import java.util.Locale

/** Bounded, session-memory diagnostics. No images, joint positions, identities,
 * network or filesystem access. A file is created only by the explicit exporter. */
internal class ArTrackingTrace(private val capacity: Int=900) {
    companion object {
        val columns=listOf("elapsed_ms","event","model","camera","source","input_age_ms","registration",
            "filter","display_safety","display_state","accepted","visible","opacity","capture_ready","yaw_deg","world_axis_yaw_deg",
            "shift_shoulders","width_ratio","height_ratio","roll_delta","yaw_delta","depth_ratio",
            "held_age_ms","candidate_count","image_ls","image_rs","image_lh","image_rh",
            "world_ls","world_rs","world_lh","world_rh","mode","residual_px","perspective_residual_px",
            "prepare_ms","pose_ms","arms_ms","target_state","detected_people","target_index","pose_backend","confirmed_profile","frame_width","frame_height","pose_model","arms_mode","arm_mask_used")
    }
    private data class Row(val time: Long,val cells: List<Any?>)
    private val rows=ArrayDeque<Row>()
    private var started: Long?=null
    val size get()=rows.size
    init { require(capacity>0) }
    fun clear() { rows.clear();started=null }
    fun record(now: Long,event: String,values: Map<String,Any?> = emptyMap()) {
        require(values.keys.all { it in columns && it !in listOf("elapsed_ms","event") })
        require(values.values.all { it==null || it is Number || it is String || it is Boolean })
        if(rows.peekLast()?.let { now<it.time }==true)clear()
        if(started==null)started=now
        val fields=values+mapOf("elapsed_ms" to now-started!!,"event" to event)
        rows.addLast(Row(now,columns.map { fields[it] }))
        while(rows.size>capacity || now-rows.first.time>180000)rows.removeFirst()
    }
    fun csv(version: Int): String = buildString {
        appendLine("# Luvly AR trace schema 3; build $version; last 3 minutes / 900 events maximum")
        appendLine("# Device-relative time and tracking diagnostics only; no images, audio, joint positions or account details")
        appendLine(columns.joinToString(","))
        rows.forEach { appendLine(it.cells.joinToString(",") { cell->encode(cell) }) }
    }
    private fun encode(value: Any?): String = when(value) {
        null -> ""
        is Float -> if(value.isFinite())String.format(Locale.US,"%.4f",value) else ""
        is Double -> if(value.isFinite())String.format(Locale.US,"%.4f",value) else ""
        is Number,is Boolean -> value.toString()
        else -> {
            var text=value.toString().replace('\r',' ').replace('\n',' ').take(96)
            if(text.trimStart().firstOrNull() in listOf('=','+','-','@'))text="'"+text
            "\""+text.replace("\"","\"\"")+"\""
        }
    }
}
