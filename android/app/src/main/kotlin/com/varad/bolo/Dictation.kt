package com.varad.bolo

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Base64
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

/**
 * One dictation: mic -> Sarvam streaming STT -> onText per phrase.
 * saaras:v4 emits a transcript at every pause, so text lands while the user is still talking.
 * stop() flushes the tail and waits briefly for the last phrase. Callbacks run on OkHttp/worker threads.
 */
class Dictation(
    ctx: Context,
    lang: String,
    mode: String,
    private val onText: (String) -> Unit,
    private val onLevel: (Float) -> Unit,
    private val onEnd: (error: String?) -> Unit,
) {
    // Debug-only: stream <external files>/test.wav (16 kHz mono PCM16) instead of the mic, for emulator tests.
    private val testWav = if (BuildConfig.DEBUG) File(ctx.getExternalFilesDir(null), "test.wav").takeIf { it.exists() } else null

    @Volatile private var recording = true
    @Volatile private var lastDataAt = 0L
    @Volatile private var ended = false
    @Volatile private var cancelled = false
    private val ws: WebSocket

    init {
        val url = "wss://api.sarvam.ai/speech-to-text/ws?model=saaras:v4&mode=$mode&language-code=$lang" +
            "&sample_rate=16000&input_audio_codec=pcm_s16le&flush_signal=true"
        val req = Request.Builder().url(url).header("api-subscription-key", BuildConfig.SARVAM_API_KEY).build()
        ws = client.newWebSocket(req, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                val msg = JSONObject(text)
                when (msg.optString("type")) {
                    "data" -> {
                        lastDataAt = System.currentTimeMillis()
                        val t = msg.optJSONObject("data")?.optString("transcript").orEmpty().trim()
                        if (t.isNotEmpty() && !cancelled) onText(t)
                    }
                    "error" -> finish(msg.optJSONObject("data")?.optString("error") ?: "Sarvam error")
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) =
                finish(response?.let { "Sarvam ${it.code}" } ?: (t.message ?: "Network error"))
        })
        thread(name = "bolo-mic") { pump() }
    }

    fun stop() { recording = false }

    /** Drop everything: no flush, no text. */
    fun cancel() { cancelled = true; finish(null) }

    @SuppressLint("MissingPermission") // checked by BoloService before constructing
    private fun pump() {
        val buf = ByteArray(3200) // 100 ms of 16 kHz PCM16
        try {
            if (testWav != null) {
                testWav.inputStream().use { input ->
                    input.skip(44) // WAV header
                    while (recording) {
                        val n = input.read(buf)
                        if (n <= 0) break
                        send(buf, n)
                        Thread.sleep(100)
                    }
                }
            } else {
                val min = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
                val rec = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16000,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, buf.size * 4))
                rec.startRecording()
                try {
                    while (recording) {
                        val n = rec.read(buf, 0, buf.size)
                        if (n > 0) send(buf, n)
                    }
                } finally {
                    rec.stop(); rec.release()
                }
            }
        } catch (e: Exception) {
            return finish("Mic error: ${e.message}")
        }
        recording = false
        val flushedAt = System.currentTimeMillis()
        ws.send("""{"type":"flush"}""")
        // Wait for the tail: done once data has gone quiet for 700 ms after the flush, capped at 4 s.
        while (!ended) {
            val now = System.currentTimeMillis()
            if (now - flushedAt > 4000 || (lastDataAt > flushedAt && now - lastDataAt > 700)) break
            Thread.sleep(50)
        }
        finish(null)
    }

    private fun send(buf: ByteArray, n: Int) {
        var sum = 0.0
        for (i in 0 until n - 1 step 2) {
            val v = ((buf[i].toInt() and 0xff) or (buf[i + 1].toInt() shl 8)).toShort().toDouble()
            sum += v * v
        }
        onLevel(minOf(1f, (Math.sqrt(sum / (n / 2)) / 4000).toFloat()))
        val b64 = Base64.encodeToString(buf, 0, n, Base64.NO_WRAP)
        ws.send("""{"audio":{"data":"$b64","sample_rate":"16000","encoding":"audio/wav"}}""")
    }

    @Synchronized private fun finish(error: String?) {
        if (ended) return
        ended = true
        recording = false
        ws.close(1000, null)
        onEnd(error)
    }

    companion object {
        private val client = OkHttpClient()
    }
}
