package com.luvly.luvly_app.ar

/** A stable detection window, not a size/beauty assessment. Clock supplied for tests. */
class PreviewReadiness {
    private var since: Long?=null
    private var last: Long?=null
    fun reset() { since=null;last=null }
    fun observe(valid: Boolean,now: Long) {
        if(!valid) { reset();return }
        if(last==null || now-last!!>700 || now<last!!)since=now
        last=now
    }
    fun ready(now: Long): Boolean = since!=null && last!=null &&
        now-last!! in 0..700 && last!!-since!!>=600
}
