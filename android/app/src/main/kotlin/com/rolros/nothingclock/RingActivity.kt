package com.rolros.nothingclock

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

private val NOTHING_RED = Color.parseColor("#D71921")

class RingActivity : Activity() {
    private var ringId = 0
    private var kind = "alarm"
    private var label = ""
    private var timeText = ""

    private val dismissReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setupWindow()
        readIntent(intent)
        buildUi()
        val filter = IntentFilter(AlarmNotifier.ACTION_DISMISSED)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(dismissReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(dismissReceiver, filter)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readIntent(intent)
        buildUi()
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(dismissReceiver)
        } catch (e: Exception) {
        }
        super.onDestroy()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // No se puede salir sin elegir apagar o posponer.
    }

    private fun setupWindow() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
        )
    }

    private fun readIntent(intent: Intent?) {
        ringId = intent?.getIntExtra("ring_id", 0) ?: 0
        kind = intent?.getStringExtra("ring_kind") ?: "alarm"
        label = intent?.getStringExtra("ring_label") ?: ""
        timeText = intent?.getStringExtra("ring_time") ?: ""
    }

    private fun buildUi() {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        val typeface: Typeface = try {
            Typeface.createFromAsset(assets, "flutter_assets/lib/fonts/NDot.ttf")
        } catch (e: Exception) {
            Typeface.MONOSPACE
        }

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.BLACK)
            setPadding(dp(28), dp(64), dp(28), dp(48))
        }

        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val dot = TextView(this).apply {
            text = "●"
            setTextColor(NOTHING_RED)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
        }
        val titleText = if (label.isNotEmpty()) label.uppercase()
        else if (kind == "timer") AlarmStrings.timer(this).uppercase()
        else AlarmStrings.alarm(this).uppercase()
        val title = TextView(this).apply {
            text = titleText
            setTextColor(0xFFA3A3A3.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            letterSpacing = 0.25f
            setPadding(dp(10), 0, 0, 0)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        headerRow.addView(dot)
        headerRow.addView(title)
        root.addView(
            headerRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        )

        val time = TextView(this).apply {
            text = timeText
            this.typeface = typeface
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 96f)
            gravity = Gravity.CENTER
            includeFontPadding = false
            maxLines = 1
        }
        root.addView(time, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f
        ))

        val snoozeMinutes = if (kind == "timer") 1 else 10
        val slide = DualSlideView(
            this,
            AlarmStrings.snooze(this, snoozeMinutes),
            AlarmStrings.stop(this),
            { doSnooze() },
            { doStop() }
        )
        root.addView(slide, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(72)
        ))

        setContentView(root)
    }

    private fun doStop() {
        AlarmNotifier.stop(applicationContext, ringId, kind)
        finish()
    }

    private fun doSnooze() {
        AlarmNotifier.snooze(applicationContext, ringId, kind, label)
        finish()
    }
}

class DualSlideView(
    context: Context,
    private val leftLabel: String,
    private val rightLabel: String,
    private val onLeft: () -> Unit,
    private val onRight: () -> Unit
) : View(context) {
    private val density = resources.displayMetrics.density
    private val scaled = resources.displayMetrics.scaledDensity
    private val pad = 6 * density

    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = density
        color = 0x99FFFFFF.toInt()
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = 11 * scaled
        letterSpacing = 0.12f
    }
    private val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        textAlign = Paint.Align.CENTER
        textSize = 20 * scaled
    }

    private var dx = 0f
    private var grabbed = false
    private var done = false
    private var downX = 0f
    private var startDx = 0f

    private fun thumbSize() = height - 2 * pad
    private fun maxDx() = (width - thumbSize() - 2 * pad) / 2f

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), (72 * density).toInt())
    }

    private fun blend(a: Int, b: Int, t: Float): Int {
        val r = (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt()
        val g = (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt()
        val bl = (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt()
        return Color.rgb(r, g, bl)
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat()
        val h = height.toFloat()
        val r = h / 2f
        canvas.drawRoundRect(
            RectF(density / 2, density / 2, w - density / 2, h - density / 2), r, r, trackPaint
        )

        val baseline = h / 2f - (textPaint.descent() + textPaint.ascent()) / 2f
        textPaint.color = if (dx < 0) Color.WHITE else 0x88FFFFFF.toInt()
        textPaint.textAlign = Paint.Align.LEFT
        canvas.drawText(leftLabel, 24 * density, baseline, textPaint)
        textPaint.color = if (dx > 0) Color.WHITE else 0x88FFFFFF.toInt()
        textPaint.textAlign = Paint.Align.RIGHT
        canvas.drawText(rightLabel, w - 24 * density, baseline, textPaint)

        val cx = w / 2f + dx
        val cy = h / 2f
        val radius = thumbSize() / 2f
        val md = maxDx()
        val p = if (md <= 0f) 0f else Math.min(1f, Math.abs(dx) / md)
        thumbPaint.color = if (dx > 0) blend(Color.WHITE, NOTHING_RED, p) else Color.WHITE
        canvas.drawCircle(cx, cy, radius, thumbPaint)
        canvas.drawText("⇄", cx, cy - (iconPaint.descent() + iconPaint.ascent()) / 2f, iconPaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (done) return true
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                val cx = width / 2f + dx
                grabbed = Math.abs(event.x - cx) <= thumbSize()
                if (grabbed) {
                    downX = event.x
                    startDx = dx
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
                return grabbed
            }
            MotionEvent.ACTION_MOVE -> {
                if (grabbed) {
                    val md = maxDx()
                    dx = (startDx + event.x - downX).coerceIn(-md, md)
                    invalidate()
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (grabbed) {
                    grabbed = false
                    val md = maxDx()
                    val p = if (md <= 0f) 0f else Math.abs(dx) / md
                    if (p > 0.85f && event.actionMasked == MotionEvent.ACTION_UP) {
                        done = true
                        val right = dx > 0
                        dx = if (right) md else -md
                        invalidate()
                        if (right) onRight() else onLeft()
                    } else {
                        dx = 0f
                        invalidate()
                    }
                }
            }
        }
        return true
    }
}
