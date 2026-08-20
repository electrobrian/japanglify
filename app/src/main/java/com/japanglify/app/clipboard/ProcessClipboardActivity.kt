package com.japanglify.app.clipboard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import com.japanglify.app.R

/**
 * Brief focused activity used to read the clipboard (and run the pipeline)
 * in cases where the background accessibility service or FGS cannot see the
 * clip because of Android's focus restrictions ("ClipboardService: Denying
 * clipboard access ... application is not in focus", the "emptied clipboard"
 * symptom after Copy in many hosts).
 *
 * The key point: we launch this *automatically* from the background paths
 * (JapanglifyAccessibilityService, ClipboardAssistService) when a normal
 * poll/clip-listener read comes back empty/unreadable. The user never has
 * to tap a "Tap to process" notification to deal with the OS protection.
 *
 * The read (and subsequent processing + rich result notification) happens
 * while this activity has (or quickly gains) focus. It finishes quickly.
 */
class ProcessClipboardActivity : Activity() {

    private var handled = false
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled) return
        handled = true

        // The clipboard may become visible a moment after we gain focus.
        // Do a short focused retry loop here so that launching us "early"
        // (as soon as the background path sees a denial) still succeeds.
        // This is what makes the emptied-clipboard case entirely automatic.
        attemptFocusedProcess(attempt = 0)
    }

    private fun attemptFocusedProcess(attempt: Int) {
        val maxAttempts = 5
        val delays = longArrayOf(0L, 40L, 120L, 280L, 520L)

        val outcome = ClipboardProcessor.processClipboardIfNew(this, force = true)

        when (outcome) {
            ClipboardProcessor.ProcessOutcome.SUCCESS -> {
                // We were launched automatically to defeat the focus/emptied-clip
                // restriction. The pipeline has already posted the rich result
                // notification (Copy / Copy image / etc.). Make sure any
                // stale "Tap to process" card is gone and exit.
                ClipboardNotifications.cancelTapToProcess(this)
                finish()
            }
            ClipboardProcessor.ProcessOutcome.DUPLICATE -> {
                val existing = LastResultStore.load(this)
                if (!existing.isNullOrEmpty()) {
                    ClipboardNotifications.showResult(this, existing)
                }
                finish()
            }
            ClipboardProcessor.ProcessOutcome.EMPTY_OR_UNREADABLE,
            ClipboardProcessor.ProcessOutcome.ERROR -> {
                if (attempt < maxAttempts - 1) {
                    mainHandler.postDelayed({
                        if (!isFinishing) attemptFocusedProcess(attempt + 1)
                    }, delays.getOrElse(attempt) { 200L })
                } else {
                    // Still unreadable even with focus. This is either a genuinely
                    // empty clipboard or a host that is actively protecting it.
                    // For the automatic "emptied clipboard after Copy" case we
                    // were launched for, just exit silently. The user will simply
                    // not see a Japanglify result notification (which is the
                    // correct signal). No extra "tap to process" or error toast.
                    finish()
                }
            }
            else -> {
                // DISABLED, NO_JAPANESE, TOO_LONG, SELF_WRITE, etc.
                finish()
            }
        }
    }

    companion object {
        /**
         * Restore foreground clipboard access without making the user approve
         * a second notification.  Android may reject a background activity
         * launch on some OEM builds; that case is intentionally silent rather
         * than turning a normal Copy into a "tap to process" chore.
         */
        fun launch(context: Context) {
            runCatching {
                context.startActivity(
                    Intent(context, ProcessClipboardActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
        }
    }
}
