package com.luvly.luvly_app.ar

import android.app.Activity
import android.os.Bundle
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Color
import android.widget.TextView
import java.io.File

/** Synthetic colour quadrants only: tests real Android bitmap rotation/mirroring. */
class FramePreparationFixtureActivity: Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val report=buildString {
            appendLine("Completed: ${System.currentTimeMillis()}")
            appendLine("Synthetic colour quadrants; no camera or personal images")
            val colours=listOf(Color.RED,Color.GREEN,Color.BLUE,Color.YELLOW)
            val expected=listOf(listOf(0,1,2,3),listOf(2,0,3,1),listOf(3,2,1,0),listOf(1,3,0,2))
            for((step,rotation) in listOf(0,90,180,270).withIndex())for(mirror in listOf(false,true)) {
                val raw=Bitmap.createBitmap(1024,768,Bitmap.Config.ARGB_8888)
                val canvas=Canvas(raw);val paint=Paint()
                for(i in 0..3) {
                    paint.color=colours[i];val x=(i%2)*512f;val y=(i/2)*384f
                    canvas.drawRect(x,y,x+512,y+384,paint)
                }
                val result=LiveCameraFrame.orient(raw,rotation,mirror)
                val sizeOk=if(rotation%180==0)result.width==640 && result.height==480
                    else result.width==480 && result.height==640
                val coloursOk=(0..3).all { i->
                    val x=((i%2+.5f)*result.width/2).toInt();val y=((i/2+.5f)*result.height/2).toInt()
                    result.getPixel(x,y)==colours[expected[step][if(mirror)i xor 1 else i]]
                }
                appendLine("${if(sizeOk && coloursOk)"PASS" else "FAIL"} rotation=$rotation mirror=$mirror ${result.width}x${result.height}")
                if(result!==raw)result.recycle();raw.recycle()
            }
        }
        File(filesDir,"ar_frame_preparation_result.txt").writeText(report)
        setContentView(TextView(this).apply { text=report;textSize=17f })
    }
}
