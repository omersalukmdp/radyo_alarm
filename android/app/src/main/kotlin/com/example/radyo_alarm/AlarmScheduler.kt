package com.example.radyo_alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import java.util.Calendar

object AlarmScheduler {
    private const val REQUEST_CODE = 7421
    const val EXTRA_URL = "radio_url"
    const val EXTRA_STATION = "radio_station"
    const val EXTRA_HOUR = "alarm_hour"
    const val EXTRA_MINUTE = "alarm_minute"
    const val EXTRA_MODE = "alarm_mode"

    private fun pendingIntent(context: Context, hour: Int = 0, minute: Int = 0, url: String = "", station: String = "", mode: String = "host"): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = "com.example.radyo_alarm.TRIGGER_ALARM"
            putExtra(EXTRA_URL, url)
            putExtra(EXTRA_STATION, station)
            putExtra(EXTRA_HOUR, hour)
            putExtra(EXTRA_MINUTE, minute)
            putExtra(EXTRA_MODE, mode)
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )
    }

    fun schedule(context: Context, hour: Int, minute: Int, url: String, station: String, mode: String) {
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context, hour, minute, url, station, mode)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pi)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pi)
        }
    }

    fun scheduleNextDay(context: Context, hour: Int, minute: Int, url: String, station: String, mode: String) {
        schedule(context, hour, minute, url, station, mode)
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context)
        alarmManager.cancel(pi)
        pi.cancel()
        val serviceIntent = Intent(context, RadioPlaybackService::class.java).setAction(RadioPlaybackService.ACTION_STOP)
        context.startService(serviceIntent)
    }
}
