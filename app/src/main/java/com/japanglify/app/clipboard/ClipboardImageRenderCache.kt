package com.japanglify.app.clipboard

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.preference.PreferenceManager
import com.japanglify.app.JapanglifyApp
import com.japanglify.app.data.PreferencesRepository
import com.japanglify.app.domain.JapanglifySettings
import com.japanglify.app.domain.OutputFormat
import java.util.concurrent.Callable
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.ThreadFactory
import java.util.concurrent.TimeUnit

/**
 * Image rendering cache with two modes:
 *
 * 1. On-demand (user explicitly tapped "Copy image"): starts work immediately
 *    and is awaited on a background thread. Uses a dedicated executor.
 *
 * 2. Preemptive (background, after we just produced a textual result):
 *    fire-and-forget cheap notification preview (and, only for short sources,
 *    a full PNG). These are tracked so we can cancel them when a newer result
 *    arrives. They run at BACKGROUND priority and are cooperative about
 *    cancellation.
 *
 * Preemptive work is safe to start because:
 * - We cancel previous preemptive jobs for an old source before starting new ones.
 * - Every completion path double-checks that the source is still the current
 *   LastResultStore.lastSource before mutating notifications or caches.
 * - The renderers themselves have early-exit checkpoints.
 * - Full preemptive renders are gated on short source length.
 *
 * Nothing here ever runs on the main thread for the heavy work.
 */
object ClipboardImageRenderCache {
    // On-demand "Copy image" from a user tap. This lane must stay responsive
    // even if a preemptive render is in flight for a previous result.
    internal val fullRenderExecutorForWrite = Executors.newSingleThreadExecutor(
        lowPrioThreadFactory("japanglify-image-ondemand")
    )

    // Preemptive background work (cheap preview always; full only for short sources).
    // Single-threaded + BACKGROUND so it cannot fan out and cannot noticeably
    // steal CPU from the foreground or from an on-demand image the user just requested.
    private val preemptiveExecutor = Executors.newSingleThreadExecutor(
        lowPrioThreadFactory("japanglify-image-preemptive")
    )

    private fun lowPrioThreadFactory(name: String) = ThreadFactory { r ->
        Thread(r, name).apply { priority = Thread.MIN_PRIORITY }
    }

    /**
     * Identity of an image, rather than merely its source text. A user who
     * tweaks width, colors, scripts, or font scale is asking for a new image;
     * Copy and Insert for an unchanged request must share the same one.
     */
    private data class RenderKey(
        val source: String,
        val settings: JapanglifySettings,
        val densityDpi: Int,
        val fontScale: Float
    )

    private data class RenderRequest(val key: RenderKey, val settings: JapanglifySettings)

    private data class Job(val key: RenderKey, val future: Future<Uri>)

    @Volatile
    private var current: Job? = null   // on-demand full render slot

    // --- Notification preview (cheap, fast, for largeIcon) ---
    private data class PreviewJob(val source: String, val future: Future<Bitmap?>)

    @Volatile
    private var currentPreviewJob: PreviewJob? = null

    @Volatile
    private var currentPreview: Pair<String, Bitmap>? = null  // (source, bitmap)

    // Preemptive full render (optional, only for short sources). If a job here
    // finishes while the source is still current, we stash the Uri so a later
    // user "Copy image" tap can be satisfied instantly.
    @Volatile
    private var preemptiveFull: Job? = null
    @Volatile
    private var preemptiveFullUri: Pair<RenderKey, Uri>? = null  // (request, uri) when done

    /**
     * Generation counter for preemptive work. Incremented on every new textual
     * result that kicks off preemptive images. Late-finishing old jobs can
     * observe a newer generation and bail without side effects.
     */
    @Volatile
    private var preemptiveGeneration: Long = 0L

    /**
     * Start a background full-fidelity render for [source].
     * Only call this when you know the user is about to need the image
     * (e.g. they tapped "Copy image"). We do not call this automatically
     * when a textual result is produced.
     */
    fun prerender(context: Context, source: String) {
        val appContext = context.applicationContext
        val request = renderRequest(appContext, source)

        // This is deliberately a one-deep cache. Copy image and Insert image
        // arrive as two actions for the same result, so reuse the running or
        // completed request instead of rendering a second PNG. A new request
        // cancels the old one; there is no history cache to accumulate.
        if (current?.key == request.key || preemptiveFull?.key == request.key ||
            preemptiveFullUri?.first == request.key) return
        current?.future?.cancel(true)
        current = Job(
            request.key,
            fullRenderExecutorForWrite.submit(Callable { renderNow(appContext, request) })
        )
    }

    /**
     * Start a cheap preview render intended only for a notification largeIcon.
     * Call only on explicit user demand for the visual; not automatically
     * at result time.
     */
    fun prerenderPreviewForNotification(context: Context, source: String) {
        val appContext = context.applicationContext
        val f = preemptiveExecutor.submit(Callable { renderPreviewNow(appContext, source, null) })
        currentPreviewJob = PreviewJob(source, f)
        preemptiveExecutor.submit {
            try {
                val bmp = f.get(8_000, TimeUnit.MILLISECONDS)
                if (bmp != null && LastResultStore.lastSource == source) {
                    currentPreview = source to bmp
                    ClipboardNotifications.attachPreviewToResult(context, source, bmp)
                }
            } catch (_: Exception) {
                // best-effort only
            }
        }
    }

    /** Returns a previously-produced cheap preview for this source, if any. */
    fun getPreview(source: String): Bitmap? {
        val p = currentPreview
        return if (p != null && p.first == source) p.second else null
    }

    /**
     * Returns the rendered image's Uri for [source] -- the in-flight/finished
     * prerender job if one matches, otherwise renders synchronously as a
     * fallback (e.g. the process was recycled between [prerender] and this
     * call, so no job survived).
     *
     * This may block the calling thread (it waits on a Future). Callers MUST
     * invoke it from a background thread when the render may be slow.
     * It is only intended for the explicit "Copy image" user action path.
     */
    fun await(context: Context, source: String): Uri {
        val request = renderRequest(context.applicationContext, source)
        // Fast path: a preemptive full render may have already finished for this exact source.
        val pre = preemptiveFullUri
        if (pre != null && pre.first == request.key) return pre.second

        val job = current
        if (job != null && job.key == request.key) {
            try {
                // No short timeout for the user-initiated write path.
                // We want to wait for a legitimately long render to finish.
                return job.future.get()
            } catch (e: ExecutionException) {
                throw e.cause ?: e
            }
        }
        // If Copy and Insert race while the optional pre-render is in flight,
        // wait for that exact job instead of starting an identical render.
        val preemptive = preemptiveFull
        if (preemptive != null && preemptive.key == request.key) {
            try {
                return preemptive.future.get()
            } catch (e: ExecutionException) {
                throw e.cause ?: e
            }
        }
        return renderNow(context.applicationContext, request)
    }

    /**
     * Same as [await], but explicitly for the "Copy image" write path from a
     * notification action. Call only from a background thread.
     */
    fun awaitForWrite(context: Context, source: String): Uri = await(context, source)

    // ── Preemptive (background after textual result) ────────────────────────────

    /**
     * Kick off preemptive background image work for a just-produced textual result.
     *
     * - Always starts the cheap notification largeIcon preview (tiny font, capped rows).
     * - Only starts a full-fidelity PNG if the source is short enough that the work
     *   is unlikely to be noticeable. Long sources are left for on-demand only.
     *
     * Previous preemptive jobs are cancelled (via generation bump + early returns).
     * Completion handlers always re-verify that the source is still current before
     * touching global state or posting notifications.
     */
    fun startPreemptive(context: Context, source: String) {
        val appContext = context.applicationContext
        // Text is the fast path. Background image preparation is an explicit,
        // opt-in convenience, never work imposed on text-only users.
        if (!PreferenceManager.getDefaultSharedPreferences(appContext)
                .getBoolean(PreferencesRepository.KEY_PREEMPTIVE_IMAGE_RENDER, false)) {
            cancelPreviousPreemptive()
            return
        }
        val request = renderRequest(appContext, source)
        val gen = ++preemptiveGeneration

        // Cancel any in-flight preemptive preview for a previous source.
        // We do not cancel on-demand work (current) — that is user-initiated.
        currentPreviewJob?.future?.cancel(true)
        currentPreviewJob = null
        preemptiveFull?.future?.cancel(true)
        // Cancellation interrupts queued/running work where possible; generation
        // checks inside the renderer are the reliable cooperative backstop.

        // Always try the cheap preview (fast, small, capped). It is the thing
        // users actually see in the notification shade.
        val previewF = preemptiveExecutor.submit(Callable {
            if (gen != preemptiveGeneration || LastResultStore.lastSource != source) return@Callable null
            renderPreviewNow(appContext, source, gen)
        })
        currentPreviewJob = PreviewJob(source, previewF)

        preemptiveExecutor.submit {
            try {
                val bmp = previewF.get(10_000, TimeUnit.MILLISECONDS)
                if (bmp != null && gen == preemptiveGeneration && LastResultStore.lastSource == source) {
                    currentPreview = source to bmp
                    ClipboardNotifications.attachPreviewToResult(context, source, bmp)
                }
            } catch (_: Exception) {
                // best effort; ignore timeouts / cancellations
            }
        }

        // Full preemptive render only for short sources. Long interlinear layout +
        // measurement + draw + PNG can be seconds of work; we do not want that
        // to run in the background for big blocks unless the user asked for it.
        if (source.length <= PREEMPTIVE_FULL_MAX_CHARS) {
            // Cancel any previous preemptive full job by replacing the handle.
            preemptiveFull = null
            preemptiveFullUri = null

            val abort = ClipboardImageRenderer.AbortCheck {
                Thread.currentThread().isInterrupted ||
                    gen != preemptiveGeneration || LastResultStore.lastSource != source
            }
            @Suppress("UNCHECKED_CAST")
            val fullF: Future<Uri> = preemptiveExecutor.submit(Callable<Uri?> {
                if (gen != preemptiveGeneration || LastResultStore.lastSource != source) return@Callable null
                runCatching { renderNow(appContext, request, abort) }.getOrNull()
            }) as Future<Uri>
            preemptiveFull = Job(request.key, fullF)

            preemptiveExecutor.submit {
                try {
                    val uri = fullF.get(60_000, TimeUnit.MILLISECONDS)
                    if (uri != null && gen == preemptiveGeneration && LastResultStore.lastSource == source) {
                        preemptiveFullUri = request.key to uri
                    }
                } catch (_: Exception) {
                    // too slow / cancelled / error — leave it; on-demand will render fresh
                }
            }
        } else {
            // For long sources we do not start a full preemptive render at all.
            preemptiveFull = null
            preemptiveFullUri = null
        }
    }

    /**
     * Best-effort cancellation of any preemptive work associated with an *old*
     * result. Called right before we accept a brand new textual result.
     * We just bump the generation; in-flight renders will observe it on their
     * next checkpoint (or on completion) and drop their results.
     */
    fun cancelPreviousPreemptive() {
        ++preemptiveGeneration
        currentPreviewJob?.future?.cancel(true)
        currentPreviewJob = null
        preemptiveFull?.future?.cancel(true)
        preemptiveFull = null
        // We intentionally do *not* clear preemptiveFullUri here — a brand new
        // startPreemptive for the *new* source will overwrite it anyway, and
        // an in-flight old one will be ignored by the lastSource check.
    }

    /** If a preemptive full render already finished for this source, return its Uri. */
    fun getPreemptiveFullUri(context: Context, source: String): Uri? {
        val p = preemptiveFullUri
        return if (p != null && p.first == renderRequest(context.applicationContext, source).key) p.second else null
    }

    // ── Internal render paths (cooperative w.r.t. generation) ──────────────────

    private fun renderRequest(context: Context, source: String): RenderRequest {
        val app = context.applicationContext as JapanglifyApp
        val baseSettings = app.preferences.load()
        val hostWidthPx = LastResultStore.lastHostFieldWidthPx
        val unitPx = ClipboardImageRenderer.fullwidthUnitPx(context)
        val hostWidthUnits = if (hostWidthPx != null && hostWidthPx > 0 && unitPx > 0f) {
            ((hostWidthPx - ClipboardImageRenderer.paddingPx(context) * 2) / unitPx)
                .toInt()
                .coerceAtLeast(6)
        } else {
            null
        }
        // The configured width is the requested wrap target. The captured
        // host field is still a useful minimum for a short selection: do not
        // create a narrow image when it is going straight back into a wider
        // chat/editor. Unlike the old heuristic, it never replaces a wider
        // width the user deliberately selected. Zero means unlimited and
        // remains unlimited regardless of the host.
        val settingsForImage = if (
            hostWidthUnits != null &&
            baseSettings.maxLineWidthFullwidth > 0
        ) {
            baseSettings.copy(
                maxLineWidthFullwidth = maxOf(
                    baseSettings.maxLineWidthFullwidth,
                    hostWidthUnits
                )
            )
        } else {
            baseSettings
        }
        val config = context.resources.configuration
        return RenderRequest(
            RenderKey(source, settingsForImage, config.densityDpi, config.fontScale),
            settingsForImage
        )
    }

    private fun renderNow(
        context: Context,
        request: RenderRequest,
        abort: ClipboardImageRenderer.AbortCheck? = null
    ): Uri {
        val app = context.applicationContext as JapanglifyApp
        val source = request.key.source
        val settingsForImage = request.settings
        val bitmap = if (settingsForImage.outputFormat == OutputFormat.INTERLINEAR) {
            val rows = checkNotNull(app.engine.buildInterlinearRows(source, settingsForImage).takeIf { it.isNotEmpty() }) {
                "No interlinear rows for source"
            }
            ClipboardImageRenderer.renderInterlinearToBitmap(context, rows, settingsForImage, abort)
        } else {
            val rendered = checkNotNull(app.engine.expand(source, settingsForImage).takeIf { it.isNotEmpty() }) {
                "Empty expansion for source"
            }
            ClipboardImageRenderer.renderToBitmap(context, rendered, settingsForImage.effectiveImageColorScheme)
        }
        return ClipboardImageRenderer.saveAndGetUri(context, bitmap)
    }

    private fun renderPreviewNow(context: Context, source: String, gen: Long?): Bitmap? {
        if (gen != null && gen != preemptiveGeneration) return null
        if (LastResultStore.lastSource != source) return null

        val abort = if (gen != null) ClipboardImageRenderer.AbortCheck { gen != preemptiveGeneration || LastResultStore.lastSource != source } else null

        return try {
            val app = context.applicationContext as JapanglifyApp
            val settings = app.preferences.load()
            if (settings.outputFormat == OutputFormat.INTERLINEAR) {
                val rows = app.engine.buildInterlinearRows(source, settings)
                if (rows.isEmpty()) null else {
                    val bmp = ClipboardImageRenderer.renderInterlinearToBitmapPreview(context, rows, settings, abort)
                    if (gen != null && gen != preemptiveGeneration) return null
                    if (LastResultStore.lastSource != source) return null
                    ClipboardImageRenderer.createNotificationPreview(bmp)
                }
            } else {
                val text = app.engine.expand(source, settings)
                if (text.isBlank()) null else {
                    val bmp = ClipboardImageRenderer.renderToBitmap(context, text, settings.effectiveImageColorScheme)
                    if (gen != null && gen != preemptiveGeneration) return null
                    if (LastResultStore.lastSource != source) return null
                    ClipboardImageRenderer.createNotificationPreview(bmp)
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private const val PREEMPTIVE_FULL_MAX_CHARS = 600
}
