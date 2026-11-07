package com.varad.bolo

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Toast

/**
 * Floating mic bubble that appears with the keyboard.
 * Hold to talk, let go to finish. Slide up while holding to lock; then tap stop to finish.
 * Each phrase is typed into the focused field as soon as Sarvam returns it.
 */
class BoloService : AccessibilityService() {
    private enum class State { IDLE, HOLD, LOCKED, FINISHING }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var wm: WindowManager
    private var state = State.IDLE
    private var dictation: Dictation? = null
    private val session = StringBuilder() // everything said this dictation, for history
    private val unplaced = StringBuilder() // words with no text box to go into
    private var lastVoiceAt = 0L

    private var bubble: FrameLayout? = null
    private lateinit var disc: ImageView
    private lateinit var halo: View
    private val discBg = GradientDrawable().apply { shape = GradientDrawable.OVAL }
    private val bubbleLp = overlayParams(touchable = true)

    private var rail: LinearLayout? = null
    private lateinit var railLock: ImageView
    private lateinit var railChevron: ImageView
    private val railLp = overlayParams(touchable = false)

    override fun onServiceConnected() {
        wm = getSystemService(WINDOW_SERVICE) as WindowManager
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) = refresh()

    override fun onInterrupt() {}

    override fun onDestroy() {
        dictation?.cancel()
        hideRail()
        bubble?.let { wm.removeView(it) }
        super.onDestroy()
    }

    /** Show the bubble while a keyboard is up (or while dictating); park it above the keyboard's right edge. */
    private fun refresh() {
        val ime = windows.firstOrNull { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD }
        if (ime == null && dictation == null) {
            bubble?.let { wm.removeView(it) }
            bubble = null
            return
        }
        val view = bubble ?: makeBubble().also { bubble = it; wm.addView(it, bubbleLp) }
        if (ime != null && state == State.IDLE) {
            val r = Rect().also(ime::getBoundsInScreen)
            bubbleLp.x = resources.displayMetrics.widthPixels - dp(BOX) - dp(2)
            bubbleLp.y = r.top - dp(BOX) - dp(64) // clear of the app's input row / send button
            wm.updateViewLayout(view, bubbleLp)
        }
    }

    private fun makeBubble(): FrameLayout {
        bubbleLp.width = dp(BOX); bubbleLp.height = dp(BOX)
        halo = View(this).apply {
            background = GradientDrawable().apply { shape = GradientDrawable.OVAL; setColor(SAFFRON) }
            alpha = 0f
        }
        disc = ImageView(this).apply {
            background = discBg
            val pad = dp(15); setPadding(pad, pad, pad, pad)
            elevation = dp(8).toFloat()
            contentDescription = "Bolo. Hold to talk, slide up to lock."
        }
        return FrameLayout(this).apply {
            clipChildren = false
            addView(halo, FrameLayout.LayoutParams(dp(DISC), dp(DISC), Gravity.CENTER))
            addView(disc, FrameLayout.LayoutParams(dp(DISC), dp(DISC), Gravity.CENTER))
            setOnTouchListener(::onTouch)
            render()
        }
    }

    // ---- Gestures ----

    private var downY = 0f
    private var downAt = 0L
    private var stopOnRelease = false

    private fun onTouch(v: View, e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> when (state) {
                State.IDLE -> if (startDictation()) {
                    state = State.HOLD
                    downY = e.rawY; downAt = SystemClock.uptimeMillis()
                    v.performHapticFeedback(HapticFeedbackConstants.VIRTUAL_KEY)
                    showRail(); render()
                }
                State.LOCKED -> stopOnRelease = true
                else -> {}
            }
            MotionEvent.ACTION_MOVE -> if (state == State.HOLD) {
                val p = ((downY - e.rawY) / dp(LOCK_DISTANCE)).coerceIn(0f, 1f)
                railLock.translationY = -p * dp(14)
                railChevron.alpha = 0.7f * (1 - p)
                if (p >= 1f) {
                    state = State.LOCKED
                    v.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                    hideRail(); render()
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> when (state) {
                State.HOLD -> {
                    hideRail()
                    if (SystemClock.uptimeMillis() - downAt < QUICK_TAP_MS) {
                        dictation?.cancel()
                        toast("Hold to talk · slide up to lock")
                    } else finishDictation()
                }
                State.LOCKED -> if (stopOnRelease) {
                    stopOnRelease = false
                    v.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
                    finishDictation()
                }
                else -> {}
            }
        }
        return true
    }

    private fun startDictation(): Boolean {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            toast("Open Bolo once to allow the microphone")
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return false
        }
        val prefs = getSharedPreferences("bolo", MODE_PRIVATE)
        session.clear(); unplaced.clear(); lastVoiceAt = SystemClock.uptimeMillis()
        dictation = Dictation(
            this,
            lang = prefs.getString("lang", "unknown")!!,
            mode = prefs.getString("mode", "transcribe")!!,
            onText = { main.post { session.appendWord(it); insert(it) } },
            onLevel = { level -> main.post { showLevel(level) } },
            onEnd = { err ->
                main.post {
                    dictation = null
                    state = State.IDLE
                    hideRail(); render()
                    if (unplaced.isNotEmpty()) {
                        copy(unplaced.toString())
                        toast("No text box here, so Bolo copied it. Paste anywhere.")
                    } else err?.let { toast(it) }
                    if (session.isNotEmpty()) History.add(this, session.toString())
                    refresh()
                }
            },
        )
        return true
    }

    private fun finishDictation() {
        dictation?.stop()
        state = State.FINISHING
        render()
    }

    // ---- Look ----

    private fun render() {
        val live = state == State.HOLD || state == State.LOCKED
        discBg.setColor(if (live) SAFFRON else INK)
        discBg.setStroke(dp(1), if (live) Color.TRANSPARENT else Color.argb(48, 255, 255, 255))
        disc.setImageResource(if (state == State.LOCKED) R.drawable.ic_stop else R.drawable.bolo_glyph)
        disc.contentDescription = if (state == State.LOCKED) "Stop dictation" else "Bolo. Hold to talk, slide up to lock."
        disc.alpha = if (state == State.FINISHING) 0.55f else 1f
        disc.animate().scaleX(if (live) 1.08f else 1f).scaleY(if (live) 1.08f else 1f).setDuration(140).start()
        if (!live) halo.animate().alpha(0f).scaleX(1f).scaleY(1f).setDuration(160).start()
    }

    /** The halo breathes with the voice: 0 = silence, 1 = loud. */
    private fun showLevel(level: Float) {
        if (state != State.HOLD && state != State.LOCKED) return
        val now = SystemClock.uptimeMillis()
        if (level > VOICE_LEVEL) lastVoiceAt = now
        if (state == State.LOCKED && now - lastVoiceAt > SILENCE_STOP_MS) {
            toast("Stopped after ${SILENCE_STOP_MS / 1000} s of silence")
            return finishDictation()
        }
        val s = 1.1f + level * 0.4f
        halo.animate().alpha(0.18f + level * 0.17f).scaleX(s).scaleY(s).setDuration(110).start()
    }

    private fun showRail() {
        if (rail != null) return
        railLock = ImageView(this).apply { setImageResource(R.drawable.ic_lock) }
        railChevron = ImageView(this).apply { setImageResource(R.drawable.ic_chevron_up); alpha = 0.7f }
        rail = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, dp(12), 0, dp(10))
            background = GradientDrawable().apply { cornerRadius = dp(22).toFloat(); setColor(Color.argb(235, 0x17, 0x17, 0x1C)) }
            addView(railLock, LinearLayout.LayoutParams(dp(20), dp(20)))
            addView(railChevron, LinearLayout.LayoutParams(dp(20), dp(20)).apply { topMargin = dp(16) })
        }
        railLp.width = dp(44); railLp.height = dp(RAIL_H)
        railLp.x = bubbleLp.x + (dp(BOX) - dp(44)) / 2
        railLp.y = bubbleLp.y + (dp(BOX) - dp(DISC)) / 2 - dp(RAIL_H) - dp(10)
        wm.addView(rail, railLp)
    }

    private fun hideRail() {
        rail?.let { wm.removeView(it) }
        rail = null
    }

    // ---- Typing ----

    /** Insert [said] at the cursor of the focused text field, adding a space if needed. */
    private fun insert(said: String) {
        val node = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: windows.firstNotNullOfOrNull { it.root?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) }
        if (node == null || !node.isEditable) return unplaced.appendWord(said).let {}
        val text = if (node.isShowingHintText) "" else node.text?.toString().orEmpty()
        var start = node.textSelectionStart; var end = node.textSelectionEnd
        if (start < 0 || end < 0 || start > text.length || end > text.length) { start = text.length; end = text.length }
        val before = text.substring(0, minOf(start, end)); val after = text.substring(maxOf(start, end))
        val chunk = (if (before.isNotEmpty() && !before.last().isWhitespace()) " " else "") + said
        val cursor = before.length + chunk.length
        val ok = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, before + chunk + after)
        })
        if (ok) {
            node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, Bundle().apply {
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, cursor)
                putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, cursor)
            })
        } else {
            // Some custom editors ignore SET_TEXT; paste works in most of them.
            copy(chunk)
            node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        }
    }

    private fun copy(text: String) =
        (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Bolo", text))

    private fun StringBuilder.appendWord(w: String) = append(if (isEmpty()) "" else " ").append(w)

    private fun toast(msg: String) = Toast.makeText(this, msg, Toast.LENGTH_SHORT).show()
    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    companion object {
        private const val BOX = 88 // bubble window: disc + room for the halo
        private const val DISC = 56
        private const val RAIL_H = 96
        private const val LOCK_DISTANCE = 96 // dp of upward slide that locks
        private const val QUICK_TAP_MS = 350L // shorter than this = a tap, not a hold
        private const val SILENCE_STOP_MS = 45_000L // locked + this long without voice = stop (saves credits)
        private const val VOICE_LEVEL = 0.06f // mic level that counts as speech; raise if a noisy room never auto-stops
        private val INK = Color.parseColor("#17171C")
        private val SAFFRON = Color.parseColor("#FF6A3D")

        private fun overlayParams(touchable: Boolean) = WindowManager.LayoutParams(
            0, 0,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY, // no "draw over apps" permission needed
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                (if (touchable) 0 else WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE),
            PixelFormat.TRANSLUCENT,
        ).apply { gravity = Gravity.TOP or Gravity.START }
    }
}

/** Last [MAX] dictations, newest first, as a JSON array in prefs. Read by MainActivity for the app's Recent list. */
object History {
    private const val MAX = 50

    fun read(ctx: android.content.Context) =
        org.json.JSONArray(ctx.getSharedPreferences("bolo", android.content.Context.MODE_PRIVATE).getString("history", "[]"))

    fun add(ctx: android.content.Context, text: String) {
        val old = read(ctx)
        val new = org.json.JSONArray().put(org.json.JSONObject().put("t", System.currentTimeMillis()).put("text", text))
        for (i in 0 until minOf(old.length(), MAX - 1)) new.put(old.get(i))
        ctx.getSharedPreferences("bolo", android.content.Context.MODE_PRIVATE).edit().putString("history", new.toString()).apply()
    }

    fun clear(ctx: android.content.Context) =
        ctx.getSharedPreferences("bolo", android.content.Context.MODE_PRIVATE).edit().remove("history").apply()
}
