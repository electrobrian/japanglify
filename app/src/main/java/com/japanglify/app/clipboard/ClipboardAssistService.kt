package com.japanglify.app.clipboard

import android.app.Service
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.ServiceCompat

/**
 * Optional foreground-service clipboard watch (no accessibility).
 * Same anti-recursion rules as [JapanglifyAccessibilityService].
 */
class ClipboardAssistService : Service() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var clipboard: ClipboardManager? = null

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        if (LastResultStore.isSuppressing()) return@OnPrimaryClipChangedListener
        mainHandler.removeCallbacks(processRunnable)
        // Read on the callback turn.  Waiting here gives Android and some
        // hosts an opportunity to clear a sensitive/ephemeral clipboard
        // before our foreground service can see the copied Japanese text.
        mainHandler.post(processRunnable)
    }

    private val processRunnable = Runnable {
        if (LastResultStore.isSuppressing()) return@Runnable
        if (!ClipboardProcessor.isAssistWanted(this)) {
            stopSelf()
            return@Runnable
        }
        when (ClipboardProcessor.processClipboardIfNew(this)) {
            ClipboardProcessor.ProcessOutcome.EMPTY_OR_UNREADABLE -> {
                if (!LastResultStore.isSuppressing()) {
                    // The platform denied/hid the clipboard to this background
                    // service ("emptied clipboard", focus restriction). Handle it
                    // entirely automatically by launching the focused shim activity.
                    // It will read with a window, process, and post the normal
                    // rich result notification. No "Tap to process" notification
                    // is required for the user.
                    ClipboardNotifications.cancelTapToProcess(this)
                    ProcessClipboardActivity.launch(this)
                }
            }
            else -> Unit
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ClipboardNotifications.ensureChannels(this)
        clipboard = getSystemService(ClipboardManager::class.java)
        clipboard?.addPrimaryClipChangedListener(clipListener)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = ClipboardNotifications.listeningNotification(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                ClipboardNotifications.ID_LISTENING,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(ClipboardNotifications.ID_LISTENING, notification)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(processRunnable)
        clipboard?.removePrimaryClipChangedListener(clipListener)
        clipboard = null
        super.onDestroy()
    }

    companion object {
        fun start(context: android.content.Context) {
            val intent = Intent(context, ClipboardAssistService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: android.content.Context) {
            context.stopService(Intent(context, ClipboardAssistService::class.java))
        }
    }
}
