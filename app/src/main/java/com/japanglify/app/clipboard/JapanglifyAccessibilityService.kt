package com.japanglify.app.clipboard

import android.accessibilityservice.AccessibilityButtonController
import android.accessibilityservice.AccessibilityService
import android.content.ClipboardManager
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.preference.PreferenceManager
import com.japanglify.app.JapanglifyApp
import com.japanglify.app.data.PreferencesRepository

/**
 * **Copy-first** assist for hosts without PROCESS_TEXT (Discord/X, …) and a
 * reliability layer even when PROCESS_TEXT is missing.
 *
 * Primary: detect Copy (clipboard change + “Copy” clicks + selection memory)
 * and post a result notification. Polls the clipboard while active so OEM
 * listener bugs cannot silence the hook.
 */
class JapanglifyAccessibilityService : AccessibilityService() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var clipboard: ClipboardManager? = null
    private var overlay: SelectionActionOverlay? = null
    private var a11yButtonCallback: AccessibilityButtonController.AccessibilityButtonCallback? = null

    @Volatile
    private var lastSelectedText: String? = null

    private var lastPolledClip: String? = null
    private var copyPipelineGeneration = 0
    private var pendingSelection: CapturedSelection? = null
    private var cutReplaceDone = false

    private val clipListener = ClipboardManager.OnPrimaryClipChangedListener {
        if (LastResultStore.isSuppressing()) return@OnPrimaryClipChangedListener
        CopyHookDiagnostics.log(this, "clipListener fired")
        scheduleCopyPipeline("clip_listener")
    }

    /** Poll clipboard even if OnPrimaryClipChangedListener is flaky. */
    private val pollRunnable = object : Runnable {
        override fun run() {
            try {
                if (!ClipboardProcessor.isAssistWanted(this@JapanglifyAccessibilityService)) {
                    return
                }
                if (LastResultStore.isSuppressing()) {
                    mainHandler.postDelayed(this, POLL_MS)
                    return
                }
                val snap = ClipboardProcessor.readClipboardSnapshot(this@JapanglifyAccessibilityService)
                val text = snap.text?.trim().orEmpty()
                if (text.isNotEmpty() &&
                    text != lastPolledClip &&
                    !LastResultStore.shouldIgnoreClipboard(
                        this@JapanglifyAccessibilityService,
                        text,
                        snap.label
                    )
                ) {
                    lastPolledClip = text
                    CopyHookDiagnostics.log(
                        this@JapanglifyAccessibilityService,
                        "poll saw new clip (${text.length} chars)"
                    )
                    scheduleCopyPipeline("poll")
                }
            } finally {
                mainHandler.postDelayed(this, POLL_MS)
            }
        }
    }

    private val hideOverlayRunnable = Runnable { overlay?.hide() }
    private val refreshPreviewRunnable = Runnable { refreshPreviewLens() }
    private val preferenceListener = SharedPreferences.OnSharedPreferenceChangeListener { _, _ ->
        // A setting edit can emit several intermediate writes. Rebuild the
        // text-only lens once from the final settings snapshot instead.
        if (overlay?.activePreviewSource() != null) {
            mainHandler.removeCallbacks(refreshPreviewRunnable)
            mainHandler.postDelayed(refreshPreviewRunnable, PREVIEW_REFRESH_DEBOUNCE_MS)
        }
    }
    /** Package that owned the text selection currently represented by the chip. */
    private var overlayHostPackage: String? = null

    private val selectionDebounce = Runnable {
        val cap = pendingSelection
        pendingSelection = null
        if (cap == null || cap.text.isBlank()) return@Runnable
        if (LastResultStore.isSelfWrite(cap.text)) return@Runnable
        lastSelectedText = cap.text
        CopyHookDiagnostics.log(this, "selection remembered (${cap.text.length} chars)")
        // Optional chip — secondary to Copy, and off unless the user opts
        // into the on-screen overlay (see wantsSelectionOverlay).
        if (ClipboardProcessor.isAssistWanted(this) && wantsSelectionOverlay()) {
            mainHandler.removeCallbacks(hideOverlayRunnable)
            overlayHostPackage = cap.packageName
            overlay?.show(cap.text, cap.bounds)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        androidx.preference.PreferenceManager
            .getDefaultSharedPreferences(this)
            .edit()
            .putBoolean(PreferencesRepository.KEY_CLIPBOARD_ASSIST, true)
            .apply()
        ClipboardNotifications.ensureChannels(this)
        clipboard = getSystemService(ClipboardManager::class.java)
        clipboard?.addPrimaryClipChangedListener(clipListener)
        overlay = SelectionActionOverlay(this)
        // onServiceConnected can be called again after a service rebind.
        // Keep exactly one listener so a single settings edit means one
        // debounced preview refresh.
        PreferenceManager.getDefaultSharedPreferences(this)
            .unregisterOnSharedPreferenceChangeListener(preferenceListener)
        PreferenceManager.getDefaultSharedPreferences(this)
            .registerOnSharedPreferenceChangeListener(preferenceListener)
        mainHandler.post(pollRunnable)
        CopyHookDiagnostics.log(this, "service connected — Copy hook active")
        // Visible proof the service is alive (not just the system a11y icon)
        ClipboardNotifications.showHookArmed(this)

        // The OS-level Accessibility Button (nav bar icon or volume-key
        // shortcut, enabled by `flagRequestAccessibilityButton` in
        // accessibility_service_config.xml) isn't a plain method override —
        // it's a callback registered on the controller Android hands back
        // here. Wired to the same on-demand clipboard processing
        // [ProcessClipboardActivity] already does for the "Tap to process"
        // notification, so it's a genuinely useful always-available trigger
        // (Japanglify whatever's currently on the clipboard, from anywhere,
        // without needing a copy event or notification first) rather than a
        // placeholder. Unregister any stale callback (onServiceConnected can
        // fire more than once if the service is rebound) before registering
        // a new one, so a button tap only launches once instead of calling
        // the old handler in addition to the new one.
        a11yButtonCallback?.let { accessibilityButtonController.unregisterAccessibilityButtonCallback(it) }
        a11yButtonCallback = object : AccessibilityButtonController.AccessibilityButtonCallback() {
            override fun onClicked(controller: AccessibilityButtonController) {
                // FLAG_ACTIVITY_NEW_TASK because a Service, not an
                // Activity, is starting this.
                startActivity(
                    Intent(this@JapanglifyAccessibilityService, ProcessClipboardActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            }
        }
        accessibilityButtonController.registerAccessibilityButtonCallback(a11yButtonCallback!!)
    }

    /**
     * Whether the floating on-screen selection chip ([SelectionActionOverlay])
     * should appear when the user selects text in another app. Read live on
     * every selection (not cached) so toggling it in Settings takes effect
     * immediately. Off by default: the chip draws over whatever app you're in
     * (real screen space, see [SelectionActionOverlay]'s
     * TYPE_ACCESSIBILITY_OVERLAY), and the Copy path plus the result
     * notification cover the core flow without it — so it's opt-in for users
     * who actually want the on-selection shortcut. Independent of the Copy
     * assist service itself: turning this off leaves Copy detection fully
     * working, it just suppresses the visual overlay.
     */
    private fun wantsSelectionOverlay(): Boolean =
        PreferenceManager.getDefaultSharedPreferences(this)
            .getBoolean(PreferencesRepository.KEY_SELECTION_OVERLAY, false)

    /**
     * Whether Cut should auto-replace the selected text in place with its
     * Japanglified form (vs. behaving like an ordinary system Cut). Read live
     * so toggling it in Settings takes effect immediately. Distinct from the
     * Copy hook — Copy only posts a result notification, whereas Cut rewrites
     * the user's field, so it gets its own opt-out — but shares the same
     * dependency on the accessibility service being connected. Default on, to
     * preserve the behavior that shipped before this toggle existed.
     */
    private fun wantsCutReplace(): Boolean =
        PreferenceManager.getDefaultSharedPreferences(this)
            .getBoolean(PreferencesRepository.KEY_CUT_REPLACE, true)

    /** Refreshes the lightweight text preview without posting another notification. */
    private fun refreshPreviewLens() {
        val source = overlay?.activePreviewSource() ?: return
        val app = applicationContext as? JapanglifyApp ?: return
        val result = runCatching { app.engine.expand(source, app.preferences.load()) }.getOrNull()
            ?: return
        LastResultStore.save(this, source, result)
        overlay?.showResultCard(source, result)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (!ClipboardProcessor.isAssistWanted(this)) {
            overlay?.hide()
            return
        }
        if (LastResultStore.isSuppressing()) return

        // Selecting/tapping inside Japanglify's own UI (e.g. the Try-it field)
        // never needs the "convert this" chip or the Copy/Cut hook — both only
        // make sense as a convenience layer for *other* apps. Without this, a
        // stray selection in our own screens (e.g. the diagnostics text) can
        // leave the accessibility-overlay chip stuck on-screen indefinitely,
        // since it only auto-hides on a window *switch*.
        if (event.packageName?.toString() == packageName) {
            overlay?.hide()
            return
        }

        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_TEXT_SELECTION_CHANGED -> {
                handleSelectionEvent(event, dismissWhenEmpty = true)
            }
            AccessibilityEvent.TYPE_VIEW_LONG_CLICKED -> {
                // Many hosts emit an empty long-click event immediately after
                // the real selection event while Android opens its selection
                // toolbar. That event does not mean the selection was cleared.
                handleSelectionEvent(event, dismissWhenEmpty = false)
            }
            AccessibilityEvent.TYPE_VIEW_CLICKED -> {
                when {
                    looksLikeCutAction(event) -> {
                        // Cut auto-replace has its own persistent opt-out
                        // ([wantsCutReplace]) on top of the shared temporary
                        // pause ([isCopyHookPaused]) — replacing text in the
                        // field is more invasive than Copy's notification, so
                        // some users want Copy on but Cut left as plain system
                        // Cut. Either being off ⇒ leave Cut as an ordinary
                        // system Cut, no auto-replace.
                        if (!ClipboardProcessor.isCopyHookPaused(this) && wantsCutReplace()) {
                            CopyHookDiagnostics.log(this, "Cut click detected — auto-replace")
                            scheduleCutAutoReplace()
                        }
                    }
                    looksLikeCopyAction(event) -> {
                        CopyHookDiagnostics.log(this, "Copy click detected")
                        scheduleCopyPipeline("copy_click")
                    }
                    else -> Unit
                }
            }
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                // Selection controls are usually rendered by System UI in a
                // separate window. Treating every window-state notification
                // as navigation made the chip vanish as soon as those
                // controls appeared. Only a real app switch dismisses it.
                if (isRealAppWindowChange(event)) overlay?.hide()
            }
            else -> Unit
        }
    }

    private fun handleSelectionEvent(
        event: AccessibilityEvent,
        dismissWhenEmpty: Boolean
    ) {
        val captured = captureSelection(event)
        if (captured != null && captured.text.isNotBlank()) {
            pendingSelection = captured
            lastSelectedText = captured.text
            mainHandler.removeCallbacks(selectionDebounce)
            mainHandler.postDelayed(selectionDebounce, 80L)
            return
        }
        if (!dismissWhenEmpty) {
            CopyHookDiagnostics.log(this, "chip kept: empty long-click event")
            return
        }

        // A collapsed selection-change event from the selected host is the
        // best signal available that the source selection was cleared.
        mainHandler.removeCallbacks(hideOverlayRunnable)
        mainHandler.postDelayed(hideOverlayRunnable, 500L)
    }

    private data class HostContext(
        val packageName: String?,
        val fieldWidthPx: Int?,
        val fieldEditable: Boolean,
        /** On-screen bounds of whatever field [fieldWidthPx] came from — see [HostFontProfiler]. */
        val fieldBoundsInScreen: Rect?
    )

    /** Best-effort host package + on-screen input width, for sizing/prioritizing "Copy Image". */
    private fun captureHostContext(): HostContext {
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return HostContext(null, null, false, null)
        return try {
            val pkg = root.packageName?.toString()
            val rect = Rect()
            val focused = try {
                root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            } catch (_: Exception) {
                null
            }
            val focusedBounds = focused?.let {
                try {
                    it.getBoundsInScreen(rect)
                    if (rect.width() > 0) Rect(rect) else null
                } finally {
                    recycleSafely(it)
                }
            }
            val bounds = focusedBounds ?: run {
                root.getBoundsInScreen(rect)
                if (rect.width() > 0) Rect(rect) else null
            }
            HostContext(pkg, bounds?.width(), focused?.isEditable == true, bounds)
        } finally {
            recycleSafely(root)
        }
    }

    /**
     * Replace the currently-focused editable field's entire contents with
     * [text] via [AccessibilityNodeInfo.ACTION_SET_TEXT]. Re-queries the live
     * focused node rather than reusing anything captured at Copy time — by
     * the time a notification action fires, the user may have scrolled or
     * refocused, so only the node that is *actually* focused right now is
     * ever written to.
     */
    fun replaceFocusedField(text: String): Boolean {
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return false
        try {
            val focused = try {
                root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            } catch (_: Exception) {
                null
            } ?: return false
            return try {
                if (!focused.isEditable) return false
                val args = android.os.Bundle().apply {
                    putCharSequence(
                        AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                        text
                    )
                }
                focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
            } finally {
                recycleSafely(focused)
            }
        } finally {
            recycleSafely(root)
        }
    }

    private fun scheduleCopyPipeline(reason: String) {
        if (!ClipboardProcessor.isAssistWanted(this)) return
        if (LastResultStore.isSuppressing()) return
        if (ClipboardProcessor.isCopyHookPaused(this)) {
            CopyHookDiagnostics.log(this, "copy hook paused — skipping ($reason)")
            return
        }

        val hostContext = captureHostContext()
        // Best-effort, async, never blocks this pipeline — see
        // HostFontProfiler's doc comment. Only benefits this host's *next*
        // copy, not this one.
        if (hostContext.fieldBoundsInScreen != null) {
            HostFontProfiler.profileAsync(this, hostContext.packageName, hostContext.fieldBoundsInScreen)
        }
        LastResultStore.rememberHost(
            hostContext.packageName,
            hostContext.fieldWidthPx,
            hostContext.fieldEditable
        )

        val gen = ++copyPipelineGeneration
        overlay?.hide()
        CopyHookDiagnostics.log(this, "pipeline start ($reason)")

        // 1) Selection memory — works when OS hides clipboard after Copy
        val selected = lastSelectedText?.trim().orEmpty()
        if (selected.isNotEmpty() && !LastResultStore.isSelfWrite(selected)) {
            when (ClipboardProcessor.processText(this, selected, force = true)) {
                ClipboardProcessor.ProcessOutcome.SUCCESS -> {
                    CopyHookDiagnostics.log(this, "processed selection OK")
                    lastPolledClip = selected
                    scheduleClipboardRetries(gen, alreadySucceeded = true)
                    return
                }
                else -> Unit
            }
        }

        scheduleClipboardRetries(gen, alreadySucceeded = false)
    }

    private fun scheduleClipboardRetries(gen: Int, alreadySucceeded: Boolean) {
        val delays = longArrayOf(0L, 30L, 80L, 180L, 350L, 600L, 1000L)
        for (delay in delays) {
            mainHandler.postDelayed({
                if (gen != copyPipelineGeneration) return@postDelayed
                if (LastResultStore.isSuppressing()) return@postDelayed
                if (!ClipboardProcessor.isAssistWanted(this)) return@postDelayed

                val forceThisAttempt = delay == 0L && !alreadySucceeded
                when (ClipboardProcessor.processClipboardIfNew(this, force = forceThisAttempt)) {
                    ClipboardProcessor.ProcessOutcome.SUCCESS -> {
                        CopyHookDiagnostics.log(this, "processed clipboard OK @${delay}ms")
                        lastPolledClip = ClipboardProcessor.readClipboard(this)?.trim()
                    }
                    ClipboardProcessor.ProcessOutcome.EMPTY_OR_UNREADABLE -> {
                        if (delay == delays.last() && !alreadySucceeded) {
                            val sel = lastSelectedText?.trim().orEmpty()
                            if (sel.isNotEmpty()) {
                                val o = ClipboardProcessor.processText(this, sel, force = true)
                                CopyHookDiagnostics.log(this, "fallback selection → $o")
                            } else {
                                // The OS/host hid the clipboard from background readers
                                // ("emptied clipboard", "not in focus"). Handle it
                                // automatically by launching our focused shim activity.
                                // It will read the clip with focus, process, and show
                                // the normal rich result notification. The user never
                                // has to tap a "Tap to process" notification.
                                CopyHookDiagnostics.log(this, "clipboard hidden/denied — auto-launch focused processor")
                                ClipboardNotifications.cancelTapToProcess(this)
                                ProcessClipboardActivity.launch(this)
                            }
                        }
                    }
                    ClipboardProcessor.ProcessOutcome.DUPLICATE,
                    ClipboardProcessor.ProcessOutcome.SELF_WRITE -> Unit
                    else -> {
                        if (delay == delays.last()) {
                            CopyHookDiagnostics.log(this, "clipboard outcome non-success")
                        }
                    }
                }
            }, delay)
        }
    }

    /**
     * Cut removes the selected span instead of leaving it in place, so it
     * can't reuse [replaceFocusedField]'s wholesale [AccessibilityNodeInfo
     * .ACTION_SET_TEXT] — that would blow away the rest of the field.
     * Instead: convert the text captured just before Cut fired, then insert
     * it at the field's cursor, which Cut collapses to exactly where the
     * removed span used to be. Retries briefly because the field's own text
     * update from the Cut may not have landed yet when the click event fires.
     */
    private fun scheduleCutAutoReplace() {
        val selected = lastSelectedText?.trim().orEmpty()
        if (selected.isBlank() || LastResultStore.isSelfWrite(selected)) {
            scheduleCopyPipeline("cut_no_selection")
            return
        }
        if (!ClipboardProcessor.containsJapanese(selected)) {
            // Plain Latin/number text: leave Cut as an ordinary system Cut —
            // nothing for Japanglify to convert, so no auto-replace either.
            CopyHookDiagnostics.log(this, "Cut ignored — no kana/kanji in selection")
            return
        }
        val app = applicationContext as? com.japanglify.app.JapanglifyApp ?: return
        val converted = runCatching {
            app.engine.expand(selected, app.preferences.load())
        }.getOrNull()
        if (converted.isNullOrEmpty()) {
            scheduleCopyPipeline("cut_engine_error")
            return
        }

        val gen = ++copyPipelineGeneration
        cutReplaceDone = false
        val delays = longArrayOf(0L, 40L, 90L, 180L, 350L)
        for (delay in delays) {
            mainHandler.postDelayed({
                if (gen != copyPipelineGeneration || cutReplaceDone) return@postDelayed
                if (insertAtCollapsedCursor(converted, selected)) {
                    cutReplaceDone = true
                    LastResultStore.save(this, selected, converted)
                    // Make the converted text available on the system clipboard too
                    // (as a self-write) so subsequent pastes and host "Copy" gestures
                    // see the Japanglified form without forcing the user to re-select.
                    LastResultStore.writeToClipboard(this, converted)
                    CopyHookDiagnostics.log(this, "cut auto-replace OK @${delay}ms")
                    // Always surface the result notification (with Copy / Copy image /
                    // Replace field / Translate actions) even on the Cut path.
                    // Without this, a successful Cut auto-replace leaves the user with
                    // the converted text in the field but no way to reach the "Copy"
                    // action or "Copy image" — exactly the trap visible when the host
                    // only offers Cut or when the user tapped Cut.
                    ClipboardNotifications.cancelTapToProcess(this)
                    ClipboardNotifications.showResult(this, converted)

                    // Preemptive background images are now allowed (generation-tracked,
                    // low-prio, length-gated, cooperative checkpoints). Cancel priors
                    // then kick the cheap preview + (for short text) a full PNG.
                    ClipboardImageRenderCache.cancelPreviousPreemptive()
                    ClipboardImageRenderCache.startPreemptive(this, converted)
                } else if (delay == delays.last()) {
                    // The host never reflected the Cut deletion within the
                    // retry window (or the field lost focus) — fall back to
                    // the normal result notification rather than leaving the
                    // user with silence and an unconverted field.
                    CopyHookDiagnostics.log(this, "cut auto-replace gave up — falling back to notification")
                    scheduleCopyPipeline("cut_race_unresolved")
                }
            }, delay)
        }
    }

    /**
     * Inserts [replacement] at the focused field's current (collapsed)
     * cursor position. Re-queries the node fresh — right after Cut is the
     * one moment we can trust the cursor to sit exactly where the removed
     * text used to start.
     */
    private fun insertAtCollapsedCursor(replacement: String, original: String): Boolean {
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return false
        try {
            val focused = try {
                root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            } catch (_: Exception) {
                null
            } ?: return false
            try {
                if (!focused.isEditable) return false
                val cursor = focused.textSelectionStart
                if (cursor < 0 || focused.textSelectionEnd != cursor) return false
                val current = focused.text?.toString().orEmpty()
                if (cursor > current.length) return false
                // Some hosts (seen on Google Keep) collapse the selection to a
                // caret before the underlying Cut deletion actually commits —
                // if the original selected text is still sitting immediately
                // before the cursor, the removal hasn't landed in this node
                // snapshot yet. Inserting now would duplicate it instead of
                // replacing it, so bail and let the retry loop try again once
                // the deletion has actually taken effect.
                if (original.isNotEmpty() && cursor >= original.length &&
                    current.substring(cursor - original.length, cursor) == original
                ) {
                    return false
                }
                val newText = current.substring(0, cursor) + replacement + current.substring(cursor)
                val setArgs = android.os.Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, newText)
                }
                val ok = focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, setArgs)
                if (ok) moveCursorAfterInsert(cursor + replacement.length)
                return ok
            } finally {
                recycleSafely(focused)
            }
        } finally {
            recycleSafely(root)
        }
    }

    private fun moveCursorAfterInsert(position: Int) {
        val root = try {
            rootInActiveWindow
        } catch (_: Exception) {
            null
        } ?: return
        try {
            val focused = try {
                root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            } catch (_: Exception) {
                null
            } ?: return
            try {
                val selArgs = android.os.Bundle().apply {
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, position)
                    putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, position)
                }
                focused.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selArgs)
            } finally {
                recycleSafely(focused)
            }
        } finally {
            recycleSafely(root)
        }
    }

    private data class CapturedSelection(
        val text: String,
        val bounds: Rect?,
        val packageName: String?
    )

    private fun captureSelection(event: AccessibilityEvent): CapturedSelection? {
        val source = event.source
        try {
            val fromEventList = event.text
                ?.mapNotNull { it?.toString() }
                ?.joinToString("")
                ?.trim()
                .orEmpty()

            if (source == null) {
                // No node info at all (e.g. WebView-rendered selection) — the
                // event's own text list is the only signal we get.
                val selected = fromEventList
                if (selected.isBlank()) return null
                return CapturedSelection(selected, null, event.packageName?.toString())
            }

            val start = source.textSelectionStart
            val end = source.textSelectionEnd
            // Node exists but reports no real range (e.g. plain cursor move) —
            // do NOT fall back to fromEventList here, or every cursor tap in a
            // populated field re-triggers the chip.
            if (start < 0 || end <= start) return null

            val bounds = Rect()
            source.getBoundsInScreen(bounds)
            val nodeText = source.text?.toString()

            val selected = when {
                nodeText != null && end <= nodeText.length ->
                    nodeText.substring(start, end)
                fromEventList.isNotEmpty() && end <= fromEventList.length ->
                    fromEventList.substring(start, end)
                else -> null
            }?.trim().orEmpty()

            if (selected.isBlank()) return null
            return CapturedSelection(
                selected,
                if (bounds.isEmpty) null else Rect(bounds),
                event.packageName?.toString()
            )
        } finally {
            if (source != null) recycleSafely(source)
        }
    }

    override fun onInterrupt() {
        overlay?.hide()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        PreferenceManager.getDefaultSharedPreferences(this)
            .unregisterOnSharedPreferenceChangeListener(preferenceListener)
        clipboard?.removePrimaryClipChangedListener(clipListener)
        clipboard = null
        a11yButtonCallback?.let { accessibilityButtonController.unregisterAccessibilityButtonCallback(it) }
        a11yButtonCallback = null
        overlay?.destroy()
        overlay = null
        CopyHookDiagnostics.log(this, "service destroyed")
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun looksLikeOurChip(event: AccessibilityEvent): Boolean {
        val t = eventLabel(event)
        return t.contains("japanglify")
    }

    private fun isRealAppWindowChange(event: AccessibilityEvent): Boolean {
        val host = overlayHostPackage ?: return false
        val changedTo = event.packageName?.toString() ?: return false
        if (changedTo == host) return false

        // Android's text-selection toolbar, keyboard and system chrome can
        // all report a window-state change while the selected app remains in
        // front. They must not dismiss an accessibility overlay anchored to
        // that selection.
        return changedTo != "android" &&
            !changedTo.startsWith("com.android.systemui") &&
            !changedTo.startsWith("com.google.android.inputmethod")
    }

    private fun looksLikeCutAction(event: AccessibilityEvent): Boolean {
        val text = eventLabel(event)
        if (text.contains("japanglify")) return false
        val cutHints = listOf("cut", "切り取り", "cut text", "cut all")
        if (cutHints.any { text.contains(it) }) return true
        val source = event.source ?: return false
        return try {
            val label = buildString {
                source.text?.let { append(it) }
                source.contentDescription?.let { append(it) }
                source.viewIdResourceName?.let { append(it) }
            }.lowercase()
            !label.contains("japanglify") && cutHints.any { label.contains(it) }
        } finally {
            recycleSafely(source)
        }
    }

    private fun looksLikeCopyAction(event: AccessibilityEvent): Boolean {
        val text = eventLabel(event)
        if (text.contains("japanglify")) return false
        val copyHints = listOf(
            "copy", "コピー", "複製", "copy link", "copy text",
            "リンクをコピー", "テキストをコピー", "内容をコピー", "copy all"
        )
        if (copyHints.any { text.contains(it) }) return true
        val source = event.source ?: return false
        return try {
            val label = buildString {
                source.text?.let { append(it) }
                source.contentDescription?.let { append(it) }
                source.viewIdResourceName?.let { append(it) }
            }.lowercase()
            !label.contains("japanglify") && copyHints.any { label.contains(it) }
        } finally {
            recycleSafely(source)
        }
    }

    private fun eventLabel(event: AccessibilityEvent): String = buildString {
        event.text?.forEach { append(it) }
        event.contentDescription?.let { append(it) }
    }.lowercase()

    private fun recycleSafely(node: AccessibilityNodeInfo) {
        try {
            @Suppress("DEPRECATION")
            node.recycle()
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val POLL_MS = 400L
        private const val PREVIEW_REFRESH_DEBOUNCE_MS = 180L

        @Volatile
        var instance: JapanglifyAccessibilityService? = null
            private set

        fun isRunning(): Boolean = instance != null
    }
}
