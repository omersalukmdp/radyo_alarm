package com.example.radyo_alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val url = intent.getStringExtra(AlarmScheduler.EXTRA_URL) ?: return
        val station = intent.getStringExtra(AlarmScheduler.EXTRA_STATION) ?: "Radyo Alarm"
        val hour = intent.getIntExtra(AlarmScheduler.EXTRA_HOUR, 7)
        val minute = intent.getIntExtra(AlarmScheduler.EXTRA_MINUTE, 0)
        val mode = intent.getStringExtra(AlarmScheduler.EXTRA_MODE) ?: "host"

        val serviceIntent = Intent(context, RadioPlaybackService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_URL, url)
            putExtra(AlarmScheduler.EXTRA_STATION, station)
            putExtra(AlarmScheduler.EXTRA_MODE, mode)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        // Alarmı her gün aynı saatte çalacak şekilde yeniden kur.
        AlarmScheduler.scheduleNextDay(context, hour, minute, url, station, mode)
    }
}
