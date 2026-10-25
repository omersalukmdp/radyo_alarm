package com.example.radyo_alarm

import android.Manifest
import android.app.AlarmManager
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.radyo_alarm/alarm"
    private val locationRequestCode = 2718
    private var pendingLocationResult: MethodChannel.Result? = null
    private var locationListener: LocationListener? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateLocation" -> {
                        if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
                            checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
                            pendingLocationResult = result
                            requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), locationRequestCode)
                        } else {
                            locateUser(result)
                        }
                    }
                    "scheduleAlarm" -> {
                        val hour = call.argument<Int>("hour")
                        val minute = call.argument<Int>("minute")
                        val url = call.argument<String>("url")
                        val station = call.argument<String>("station")
                        val mode = call.argument<String>("mode") ?: "host"
                        if (hour == null || minute == null || url.isNullOrBlank() || station.isNullOrBlank()) {
                            result.error("BAD_ARGUMENTS", "Alarm bilgileri eksik.", null)
                            return@setMethodCallHandler
                        }
                        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName"))
                            startActivity(intent)
                            result.error("EXACT_ALARM_PERMISSION", "Android ayarlarından kesin alarm iznini ver, sonra alarmı tekrar aç.", null)
                            return@setMethodCallHandler
                        }
                        AlarmScheduler.schedule(this, hour, minute, url, station, mode)
                        result.success(true)
                    }
                    "cancelAlarm" -> {
                        AlarmScheduler.cancel(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == locationRequestCode) {
            val result = pendingLocationResult
            pendingLocationResult = null
            if (result == null) return
            if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
                checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
                locateUser(result)
            } else {
                result.error("LOCATION_PERMISSION", "Konum izni verilmedi. İstanbul varsayılan olarak kullanılacak.", null)
            }
        }
    }

    @Suppress("MissingPermission")
    private fun locateUser(result: MethodChannel.Result) {
        val manager = getSystemService(LOCATION_SERVICE) as LocationManager
        val providers = manager.getProviders(true)
        var best: Location? = null
        for (provider in providers) {
            try {
                val location = manager.getLastKnownLocation(provider)
                if (location != null && (best == null || location.time > best.time)) best = location
            } catch (_: Exception) { }
        }
        if (best != null) {
            saveAndReturnLocation(best!!, result)
            return
        }

        // No cached fix: request a single fresh location, then stop listening.
        val provider = when {
            providers.contains(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER
            providers.contains(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            else -> null
        }
        if (provider == null) {
            result.error("LOCATION_OFF", "Konum servisleri kapalı. Telefon ayarlarından konumu açıp tekrar dene.", null)
            return
        }
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                try { manager.removeUpdates(this) } catch (_: Exception) { }
                mainHandler.removeCallbacksAndMessages(this)
                locationListener = null
                saveAndReturnLocation(location, result)
            }
            @Deprecated("Deprecated by Android") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        locationListener = listener
        try {
            manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
            mainHandler.postAtTime({
                try { manager.removeUpdates(listener) } catch (_: Exception) { }
                if (locationListener === listener) {
                    locationListener = null
                    result.error("LOCATION_TIMEOUT", "Konum alınamadı. Konum servisini açıp açık alanda tekrar dene.", null)
                }
            }, listener, android.os.SystemClock.uptimeMillis() + 15000L)
        } catch (e: Exception) {
            locationListener = null
            result.error("LOCATION_FAILED", "Konum alınamadı: ${e.localizedMessage ?: "bilinmeyen hata"}", null)
        }
    }

    private fun saveAndReturnLocation(location: Location, result: MethodChannel.Result) {
        var city = "Bulunduğun bölge"
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Geocoder(this, Locale("tr", "TR")).getFromLocation(location.latitude, location.longitude, 1) { addresses ->
                    city = addresses.firstOrNull()?.locality
                        ?: addresses.firstOrNull()?.subAdminArea
                        ?: addresses.firstOrNull()?.adminArea
                        ?: city
                    saveLocation(location, city, result)
                }
            } else {
                @Suppress("DEPRECATION")
                val address = Geocoder(this, Locale("tr", "TR")).getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull()
                city = address?.locality ?: address?.subAdminArea ?: address?.adminArea ?: city
                saveLocation(location, city, result)
            }
        } catch (_: Exception) {
            saveLocation(location, city, result)
        }
    }

    private fun saveLocation(location: Location, city: String, result: MethodChannel.Result) {
        getSharedPreferences("radyo_alarm_location", MODE_PRIVATE).edit()
            .putFloat("latitude", location.latitude.toFloat())
            .putFloat("longitude", location.longitude.toFloat())
            .putString("city", city)
            .apply()
        runOnUiThread {
            result.success(mapOf("latitude" to location.latitude, "longitude" to location.longitude, "city" to city))
        }
    }
}
