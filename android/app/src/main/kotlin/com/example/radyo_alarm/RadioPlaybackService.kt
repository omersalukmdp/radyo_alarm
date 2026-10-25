package com.example.radyo_alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.concurrent.thread

class RadioPlaybackService : Service() {
    companion object {
        const val ACTION_STOP = "com.example.radyo_alarm.STOP_RADIO"
        private const val CHANNEL_ID = "radio_alarm_playback"
        private const val NOTIFICATION_ID = 7422
        private const val UTTERANCE_ID = "morning_bulletin"
        private const val MODE_HOST = "host"
        private const val MODE_RADIO = "radio"
        private const val MODE_HOST_RADIO = "host_radio"
    }

    private var tts: TextToSpeech? = null
    private var radioPlayer: MediaPlayer? = null
    private var introTrack: AudioTrack? = null
    private var mode: String = MODE_HOST
    private var radioUrl: String = ""
    private var radioName: String = "Radyo"
    @Volatile private var stopped = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopPlayback()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        stopped = false
        mode = intent?.getStringExtra(AlarmScheduler.EXTRA_MODE) ?: MODE_HOST
        radioUrl = intent?.getStringExtra(AlarmScheduler.EXTRA_URL) ?: ""
        radioName = intent?.getStringExtra(AlarmScheduler.EXTRA_STATION) ?: "Radyo"
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())

        if (mode == MODE_RADIO) {
            startRadio()
        } else {
            thread(name = "morning-weather-fetch") {
                val script = buildMorningScript()
                if (stopped) return@thread
                Handler(mainLooper).post {
                    if (!stopped) playGentleIntroThenSpeak(script)
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun buildMorningScript(): String {
        val locale = Locale("tr", "TR")
        val dateFormat = SimpleDateFormat("d MMMM EEEE", locale).apply {
            timeZone = TimeZone.getDefault()
        }
        val dateText = dateFormat.format(Date())
        val savedLocation = getSharedPreferences("radyo_alarm_location", MODE_PRIVATE)
        val latitude = savedLocation.getFloat("latitude", 41.0082f).toDouble()
        val longitude = savedLocation.getFloat("longitude", 28.9784f).toDouble()
        val city = savedLocation.getString("city", "İstanbul")?.takeIf { it.isNotBlank() } ?: "İstanbul"
        return try {
            val url = URL(
                "https://api.open-meteo.com/v1/forecast" +
                    "?latitude=$latitude&longitude=$longitude" +
                    "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m" +
                    "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max,sunrise" +
                    "&timezone=auto&forecast_days=1"
            )
            val connection = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 7000
                readTimeout = 7000
                requestMethod = "GET"
            }
            val body = connection.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            connection.disconnect()
            val root = JSONObject(body)
            val current = root.getJSONObject("current")
            val daily = root.getJSONObject("daily")
            val temp = current.getDouble("temperature_2m").toInt()
            val feels = current.getDouble("apparent_temperature").toInt()
            val condition = weatherDescription(current.getInt("weather_code"))
            val wind = current.optDouble("wind_speed_10m", -1.0).toInt()
            val max = daily.getJSONArray("temperature_2m_max").getDouble(0).toInt()
            val min = daily.getJSONArray("temperature_2m_min").getDouble(0).toInt()
            val rainArray = daily.optJSONArray("precipitation_probability_max")
            val rain = if (rainArray != null && !rainArray.isNull(0)) rainArray.optInt(0, -1) else -1
            val maxWindArray = daily.optJSONArray("wind_speed_10m_max")
            val maxWind = if (maxWindArray != null && !maxWindArray.isNull(0)) maxWindArray.optInt(0, -1) else -1
            val rainSentence = if (rain >= 40) " Yağış ihtimali yüzde $rain." else ""
            val maxWindSentence = if (maxWind >= 30 || wind >= 25) " Rüzgâr zaman zaman kuvvetlenebilir." else ""
            "Günaydın! Bugün $dateText. $city'de hava $condition, sıcaklık şu anda $temp derece. " +
                "Günün en yüksek sıcaklığı $max, en düşük sıcaklığı $min derece olacak." +
                rainSentence + maxWindSentence + " Güzel bir gün dilerim."
        } catch (_: Exception) {
            "Günaydın! Bugün $dateText. Şu anda hava durumunu alamadım. Güncel tahmini kontrol etmeyi unutma. Güzel bir gün dilerim."

        }
    }

    private fun weatherDescription(code: Int): String = when (code) {
        0 -> "açık"
        1 -> "çoğunlukla açık"
        2 -> "parçalı bulutlu"
        3 -> "kapalı"
        45, 48 -> "sisli"
        in 51..57 -> "çiseli"
        in 61..67 -> "yağmurlu"
        in 71..77 -> "kar yağışlı"
        in 80..82 -> "sağanak yağışlı"
        85, 86 -> "kar sağanaklı"
        in 95..99 -> "gök gürültülü fırtınalı"
        else -> "değişken"
    }

    /** Plays a quiet, synthesized three-note morning chime before the spoken bulletin. */
    private fun playGentleIntroThenSpeak(script: String) {
        if (stopped) return
        val sampleRate = 44100
        val durationSeconds = 4.2
        val sampleCount = (sampleRate * durationSeconds).toInt()
        val pcm = ShortArray(sampleCount)
        val notes = listOf(
            Triple(523.25, 0.10, 1.45),
            Triple(659.25, 1.35, 1.55),
            Triple(783.99, 2.55, 1.45)
        )
        for (i in 0 until sampleCount) {
            val t = i.toDouble() / sampleRate
            var sample = 0.0
            for ((frequency, start, length) in notes) {
                val local = t - start
                if (local >= 0.0 && local <= length) {
                    val attack = (local / 0.28).coerceIn(0.0, 1.0)
                    val release = ((length - local) / 0.48).coerceIn(0.0, 1.0)
                    val envelope = attack * release
                    // Soft, rounded chime with a very quiet overtone; intentionally low volume.
                    sample += (kotlin.math.sin(2.0 * Math.PI * frequency * local) * 0.72 +
                        kotlin.math.sin(2.0 * Math.PI * frequency * 2.0 * local) * 0.08) * envelope
                }
            }
            // Keep the intro intentionally subtle so it eases the listener awake.
            pcm[i] = (sample * 1800.0).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
        }

        try {
            introTrack?.release()
            val minBuffer = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            introTrack = AudioTrack(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build(),
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
                maxOf(minBuffer, pcm.size * 2),
                AudioTrack.MODE_STATIC,
                AudioManager.AUDIO_SESSION_ID_GENERATE
            ).apply {
                setVolume(0.28f)
                write(pcm, 0, pcm.size)
                play()
            }
            Handler(mainLooper).postDelayed({
                try { introTrack?.release() } catch (_: Exception) {}
                introTrack = null
                if (!stopped) startSpeaking(script)
            }, (durationSeconds * 1000).toLong() + 250L)
        } catch (_: Exception) {
            try { introTrack?.release() } catch (_: Exception) {}
            introTrack = null
            // If audio playback is unavailable, don't block the actual alarm speech.
            Handler(mainLooper).postDelayed({ if (!stopped) startSpeaking(script) }, 300L)
        }
    }

    private fun startSpeaking(script: String) {
        try { tts?.stop(); tts?.shutdown() } catch (_: Exception) {}
        tts = TextToSpeech(this) { status ->
            if (stopped) return@TextToSpeech
            val engine = tts ?: return@TextToSpeech
            if (status != TextToSpeech.SUCCESS) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return@TextToSpeech
            }
            engine.language = Locale("tr", "TR")
            // Use the best Turkish voice installed on the device; network voices are often more natural.
            val turkishVoice = engine.voices
                ?.filter { it.locale.language.equals("tr", ignoreCase = true) }
                ?.maxByOrNull { it.quality + if (it.isNetworkConnectionRequired) 1000 else 0 }
            if (turkishVoice != null) engine.voice = turkishVoice
            engine.setSpeechRate(0.94f)
            engine.setPitch(1.0f)
            engine.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) {
                    Handler(mainLooper).post {
                        try { tts?.shutdown() } catch (_: Exception) {}
                        tts = null
                        if (mode == MODE_HOST_RADIO && !stopped) {
                            startRadio()
                        } else {
                            stopForeground(STOP_FOREGROUND_REMOVE)
                            stopSelf()
                        }
                    }
                }
                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    Handler(mainLooper).post {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        stopSelf()
                    }
                }
            })
            engine.speak(script, TextToSpeech.QUEUE_FLUSH, null, UTTERANCE_ID)
        }
    }

    private fun startRadio() {
        if (radioUrl.isBlank()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        try {
            radioPlayer?.release()
            radioPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                setDataSource(radioUrl)
                setOnPreparedListener { media -> if (!stopped) media.start() }
                setOnErrorListener { _, _, _ ->
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                    true
                }
                prepareAsync()
            }
        } catch (_: Exception) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun stopPlayback() {
        stopped = true
        try { tts?.stop(); tts?.shutdown() } catch (_: Exception) {}
        tts = null
        try { introTrack?.pause() } catch (_: Exception) {}
        try { introTrack?.release() } catch (_: Exception) {}
        introTrack = null
        try { radioPlayer?.stop() } catch (_: Exception) {}
        try { radioPlayer?.release() } catch (_: Exception) {}
        radioPlayer = null
    }

    private fun buildNotification(): Notification {
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentPendingIntent = openIntent?.let {
            PendingIntent.getActivity(
                this, 7423, it,
                PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
            )
        }
        val stopIntent = Intent(this, RadioPlaybackService::class.java).setAction(ACTION_STOP)
        val stopPendingIntent = PendingIntent.getService(
            this, 7424, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID) else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val title = if (mode == MODE_RADIO) "Alarm radyosu: $radioName" else "Günaydın!"
        val description = when (mode) {
            MODE_RADIO -> "$radioName yayını çalıyor"
            MODE_HOST_RADIO -> "Sabah bülteni, ardından $radioName"
            else -> "Sabah konuşması ve hava durumu hazırlanıyor"
        }
        builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(description)
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_pause, "Durdur", stopPendingIntent)
        if (contentPendingIntent != null) builder.setContentIntent(contentPendingIntent)
        return builder.build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Sabah alarmı", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        stopPlayback()
        super.onDestroy()
    }
}
