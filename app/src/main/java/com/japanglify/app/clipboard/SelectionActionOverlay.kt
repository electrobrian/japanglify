package com.japanglify.app.clipboard

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import com.japanglify.app.R
import com.japanglify.app.SettingsActivity

/**
 * Accessibility overlay chip and floating result card.
 * Uses [WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY] — granted directly to
 * enabled AccessibilityServices without requiring root or extra permissions.
 */
class SelectionActionOverlay(
    private val service: AccessibilityService
) {
    private val windowManager =
        service.getSystemService(WindowManager::class.java)

    // Chip overlay
    private var chipRoot: FrameLayout? = null
    private var pendingText: String? = null

    // Floating Result Card Overlay
    private var cardRoot: FrameLayout? = null
    private var previewSource: String? = null

    fun show(text: String, anchorOnScreen: Rect?) {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || trimmed.length > ClipboardProcessor.MAX_CHARS) {
            hide()
            return
        }
        pendingText = trimmed
        ensureChipView()
        val view = chipRoot ?: return
        val params = view.layoutParams as WindowManager.LayoutParams
        val density = service.resources.displayMetrics
        val margin = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, 8f, density
        ).toInt()
        val approxChipH = TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP, 44f, density
        ).toInt()

        if (anchorOnScreen != null && !anchorOnScreen.isEmpty) {
            params.gravity = Gravity.TOP or Gravity.START
            params.x = (anchorOnScreen.left).coerceAtLeast(margin)
            val below = anchorOnScreen.bottom + margin
            val screenH = density.heightPixels
            params.y = if (below + approxChipH < screenH - margin) {
                below
            } else {
                (anchorOnScreen.top - approxChipH - margin).coerceAtLeast(margin)
            }
        } else {
            params.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            params.x = 0
            params.y = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, 72f, density
            ).toInt()
        }
        try {
            windowManager.updateViewLayout(view, params)
            view.visibility = View.VISIBLE
        } catch (_: Exception) {
            try {
                windowManager.addView(view, params)
            } catch (_: Exception) {
                // ignore
            }
        }
    }

    fun hide() {
        pendingText = null
        chipRoot?.visibility = View.GONE
    }

    fun showResultCard(sourceText: String, resultText: String) {
        hide()
        previewSource = sourceText
        ensureCardView()
        val card = cardRoot ?: return

        card.findViewById<TextView>(R.id.card_result_text)?.text = resultText

        card.findViewById<ImageButton>(R.id.btn_dismiss)?.setOnClickListener {
            hideResultCard()
        }

        card.findViewById<Button>(R.id.btn_copy)?.setOnClickListener {
            LastResultStore.writeToClipboard(service, resultText)
            Toast.makeText(service, R.string.notif_copied_ready_to_paste, Toast.LENGTH_SHORT).show()
            hideResultCard()
        }

        card.findViewById<Button>(R.id.btn_copy_image)?.setOnClickListener {
            service.startActivity(
                Intent(service, ClipboardWriteActivity::class.java)
                    .setAction(ClipboardAssistReceiver.ACTION_COPY_IMAGE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            hideResultCard()
        }

        card.findViewById<Button>(R.id.btn_settings)?.setOnClickListener {
            service.startActivity(
                Intent(service, SettingsActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }

        try {
            card.visibility = View.VISIBLE
        } catch (_: Exception) {
            // ignore
        }
    }

    fun hideResultCard() {
        previewSource = null
        cardRoot?.visibility = View.GONE
    }

    fun activePreviewSource(): String? =
        previewSource?.takeIf { cardRoot?.visibility == View.VISIBLE }

    fun destroy() {
        hide()
        hideResultCard()
        chipRoot?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
        }
        cardRoot?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
        }
        chipRoot = null
        cardRoot = null
        pendingText = null
    }

    private fun overlayWindowType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
        }
    }

    private fun ensureChipView() {
        if (chipRoot != null) return
        val view = LayoutInflater.from(service)
            .inflate(R.layout.overlay_japanglify_chip, null) as FrameLayout
        view.findViewById<TextView>(R.id.chip_label).setOnClickListener {
            onChipClicked()
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START
        try {
            windowManager.addView(view, params)
            chipRoot = view
        } catch (_: Exception) {
            chipRoot = null
        }
    }

    private fun ensureCardView() {
        if (cardRoot != null) return
        val view = LayoutInflater.from(service)
            .inflate(R.layout.overlay_result_card, null) as FrameLayout

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.CENTER
        try {
            windowManager.addView(view, params)
            cardRoot = view
        } catch (_: Exception) {
            cardRoot = null
        }
    }

    private fun onChipClicked() {
        val text = pendingText?.trim().orEmpty()
        hide()
        if (text.isEmpty()) return
        when (ClipboardProcessor.processText(service, text)) {
            ClipboardProcessor.ProcessOutcome.SUCCESS -> {
                val result = LastResultStore.load(service).orEmpty()
                if (result.isNotEmpty()) {
                    showResultCard(sourceText = text, resultText = result)
                } else {
                    Toast.makeText(
                        service,
                        R.string.notif_result_ready,
                        Toast.LENGTH_SHORT
                    ).show()
                }
            }
            ClipboardProcessor.ProcessOutcome.DISABLED -> {
                Toast.makeText(
                    service,
                    R.string.clipboard_assist_disabled_hint,
                    Toast.LENGTH_LONG
                ).show()
            }
            else -> {
                Toast.makeText(
                    service,
                    R.string.error_processing_generic,
                    Toast.LENGTH_SHORT
                ).show()
            }
        }
    }
}
