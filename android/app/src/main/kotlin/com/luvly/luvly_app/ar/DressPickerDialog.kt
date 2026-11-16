package com.luvly.luvly_app.ar

import android.app.Dialog
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.Window
import android.widget.*

/** Local catalogue photos only: no network, camera image upload or second 3D renderer. */
class DressPickerDialog(context: Context, choices: List<ArDress>, currentId: String?,
                        unsavedPreview: Boolean, private val onChoose: (ArDress)->Unit): Dialog(context) {
    private val rose=Color.rgb(161,79,98)
    private val ink=Color.rgb(65,42,47)
    private var selected=choices.firstOrNull { it.id==currentId } ?: choices.first()
    private val rows=mutableListOf<Pair<ArDress,LinearLayout>>()
    private val badges=mutableMapOf<String,TextView>()
    private fun dp(n: Int)=(n*context.resources.displayMetrics.density).toInt()
    private fun text(value: String,size: Float,color: Int=ink)=TextView(context).apply {
        text=value;textSize=size;setTextColor(color)
    }
    private fun background(fill: Int,stroke: Int=fill)=GradientDrawable().apply {
        setColor(fill);cornerRadius=dp(16).toFloat();setStroke(dp(2),stroke)
    }
    private val confirm=Button(context)

    init {
        requestWindowFeature(Window.FEATURE_NO_TITLE)
        val page=LinearLayout(context).apply {
            orientation=LinearLayout.VERTICAL;setPadding(dp(20),dp(16),dp(20),dp(16))
            background=background(Color.rgb(252,247,244))
        }
        val heading=LinearLayout(context).apply { gravity=Gravity.CENTER_VERTICAL }
        heading.addView(text("Choose your dress",22f).apply { setTypeface(null,Typeface.BOLD) },
            LinearLayout.LayoutParams(0,-2,1f))
        heading.addView(Button(context).apply {
            text="Close";isAllCaps=false;setTextColor(rose)
            background=background(Color.TRANSPARENT);elevation=0f
            setOnClickListener { dismiss() }
        })
        page.addView(heading)
        page.addView(text("Compare the styles, then try your favourite.",14f).apply {
            setPadding(0,dp(6),0,dp(12))
        })
        val list=LinearLayout(context).apply { orientation=LinearLayout.VERTICAL }
        page.addView(ScrollView(context).apply { isFillViewport=false;addView(list) },
            LinearLayout.LayoutParams(-1,0,1f))
        for(dress in choices) {
            val row=LinearLayout(context).apply {
                orientation=LinearLayout.HORIZONTAL;gravity=Gravity.CENTER_VERTICAL
                setPadding(dp(8),dp(8),dp(10),dp(8));isFocusable=true;isClickable=true
                contentDescription="${dress.name}. ${dress.style}."+
                    if(dress.id==currentId) " Currently trying on." else " Select dress."
                setOnClickListener { selected=dress;refresh(currentId) }
            }
            val photo=ImageView(context).apply {
                scaleType=ImageView.ScaleType.FIT_CENTER
                setBackgroundColor(Color.rgb(235,230,229))
                importantForAccessibility=View.IMPORTANT_FOR_ACCESSIBILITY_NO
                // Decode a bounded thumbnail; never allocate a full-size camera photo here.
                val bitmap=runCatching {
                    context.assets.open("flutter_assets/${dress.thumbnail}").use {
                        BitmapFactory.decodeStream(it,null,BitmapFactory.Options().apply { inSampleSize=2 })
                    }
                }.getOrNull()
                if(bitmap!=null) {
                    // This render has wide empty studio margins. Focus its display
                    // crop on the actual gown; the original asset stays unchanged.
                    val display=if(dress.id=="elegant-local-review") android.graphics.Bitmap.createBitmap(bitmap,
                        (bitmap.width*.16f).toInt(),(bitmap.height*.29f).toInt(),
                        (bitmap.width*.68f).toInt(),(bitmap.height*.46f).toInt()) else bitmap
                    setImageBitmap(display)
                    if(display!==bitmap)bitmap.recycle()
                } else setImageResource(android.R.drawable.ic_menu_gallery)
            }
            row.addView(photo,LinearLayout.LayoutParams(dp(108),dp(148)))
            val details=LinearLayout(context).apply {
                orientation=LinearLayout.VERTICAL;setPadding(dp(14),0,0,0)
            }
            details.addView(text(dress.name,18f).apply { setTypeface(null,Typeface.BOLD) })
            details.addView(text(dress.style,13f).apply { setPadding(0,dp(8),0,dp(8)) })
            val badge=text("",13f,rose).apply { setTypeface(null,Typeface.BOLD) }
            badges[dress.id]=badge;details.addView(badge)
            row.addView(details,LinearLayout.LayoutParams(0,-2,1f))
            rows.add(dress to row)
            list.addView(row,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=dp(12) })
        }
        page.addView(text(if(unsavedPreview) "Switching starts a new preview. Save your current look first if you want to keep it."
            else "3D style previews · Not a size or fit assessment",12f).apply {
            setPadding(0,dp(10),0,dp(8))
        })
        confirm.apply {
            isAllCaps=false;textSize=16f;minHeight=dp(50);setTextColor(Color.WHITE)
            setOnClickListener {
                if(selected.id!=currentId) { dismiss();onChoose(selected) }
            }
        }
        page.addView(confirm,LinearLayout.LayoutParams(-1,-2))
        setContentView(page)
        setCanceledOnTouchOutside(true)
        refresh(currentId)
    }

    private fun refresh(currentId: String?) {
        for((dress,row) in rows) {
            val chosen=dress.id==selected.id
            row.isSelected=chosen
            row.background=background(Color.WHITE,if(chosen)rose else Color.rgb(234,222,224))
            badges[dress.id]?.text=when {
                dress.id==currentId -> "Currently trying on"
                chosen -> "✓ Selected"
                else -> "Tap to select"
            }
        }
        confirm.isEnabled=selected.id!=currentId
        confirm.text=if(confirm.isEnabled) "Try ${selected.name}" else "Currently trying on"
        confirm.background=background(if(confirm.isEnabled)rose else Color.rgb(171,158,160))
    }

    override fun onStart() {
        super.onStart()
        window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            val metrics=context.resources.displayMetrics
            setLayout(minOf(metrics.widthPixels-dp(24),dp(560)),(metrics.heightPixels*.84f).toInt())
            setGravity(Gravity.CENTER)
        }
    }
}
