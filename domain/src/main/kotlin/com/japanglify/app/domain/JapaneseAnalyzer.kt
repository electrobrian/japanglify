package com.japanglify.app.domain

import com.japanglify.app.domain.dictionary.GlossAnnotator
import com.japanglify.app.domain.emoji.EmojiAnnotator

/**
 * Turns raw selected text into a list of [AnnotatedSegment]s carrying
 * surface form, hiragana furigana, and romaji.
 *
 * Uses an optional [ReadingProvider] (typically Kuromoji on device) for
 * kanji readings. When no provider is available, pure-kana text is still
 * fully annotated; kanji is left without furigana.
 *
 * [glossAnnotator] is likewise optional and degrades the same way: no
 * dictionary downloaded yet (or glosses off in settings) just means every
 * segment's `gloss` stays null, same as furigana/romaji without a provider.
 *
 * [emojiAnnotator] is a second, optional pass layered on top of the gloss
 * result (see [EmojiAnnotator]'s doc) — degrades the same way again: no
 * emoji data downloaded, or the feature off in settings, just means every
 * segment's `emoji` stays null and `gloss` is left exactly as the gloss
 * pass produced it.
 */
class JapaneseAnalyzer(
    private val readingProvider: ReadingProvider? = null,
    private val glossAnnotator: GlossAnnotator? = null,
    private val emojiAnnotator: EmojiAnnotator? = null
) {

    fun interface ReadingProvider {
        /**
         * Tokenize [text] into surface/reading pairs.
         * [reading] should be katakana or hiragana; use null/"*" for unknown.
         */
        fun tokenize(text: String): List<SurfaceReading>
    }

    data class SurfaceReading(
        val surface: String,
        val reading: String?,
        /** True for an auxiliary-verb/conjugation-ending token (e.g. ました, ない). */
        val isBoundToPrevious: Boolean = false,
        /** True for a grammatical particle (は/を/の/に/…). */
        val isParticle: Boolean = false,
        /**
         * True only when the morphological provider identifies this token as
         * a proper noun in context. Proper nouns retain their reading and
         * romaji, but must not inherit an unrelated common-word gloss/emoji.
         * False when a provider is unavailable or the spelling is ambiguous.
         */
        val isProperNoun: Boolean = false,
        /**
         * Dictionary/base form (Kuromoji's `getBaseForm()`) — the lookup key
         * for [com.japanglify.app.domain.dictionary.GlossAnnotator], e.g.
         * 行き's base form is 行く. Null when unavailable (no provider, or a
         * merged multi-token span with no single base form of its own — see
         * `KuromojiReadingProvider.mergeConsecutiveNumbers`).
         */
        val baseForm: String? = null,
        /**
         * The matching JMdict verb-class code prefix ("v5r", "vs", "v1",
         * "vk", ...) for this token's own conjugation, derived from
         * Kuromoji's conjugation-type classification via
         * [com.japanglify.app.domain.dictionary.jmdictVerbConjugationPrefix]
         * — see that function's doc for why this exists (disambiguating
         * same-reading, same-spelling-in-kana but otherwise unrelated JMdict
         * words, e.g. する "to do" vs 擦る "to rub"). Null for non-verb
         * tokens or conjugation types Kuromoji doesn't classify this way.
         */
        val verbPosHint: String? = null
    )

    fun annotate(text: String, settings: JapanglifySettings): List<AnnotatedSegment> {
        if (text.isEmpty()) return emptyList()

        val romanizer = Romanizer(settings.romanizationSystem)
        val tokens = readingProvider?.tokenize(text) ?: fallbackTokenize(text)
        val glossResults = if (settings.includeGlosses) {
            glossAnnotator?.annotate(tokens, settings.effectiveSenseWeights, settings.maxGlossLength)
                ?: List(tokens.size) { GlossAnnotator.TokenGloss(null) }
        } else {
            List(tokens.size) { GlossAnnotator.TokenGloss(null) }
        }
        // Only meaningful once glosses are actually resolved -- matches
        // against a token's *gloss text*, never the Japanese word itself,
        // so with glosses off glossResults is already all-null and this
        // naturally yields all-null too via EmojiAnnotator's own null check.
        val emojis = if (settings.includeEmoji) {
            emojiAnnotator?.annotate(glossResults.map { it.result }, settings.emojiPosScope, settings.emojiPrecisionTier)
                ?: List(tokens.size) { null }
        } else {
            List(tokens.size) { null }
        }

        return tokens.mapIndexed { i, token ->
            val emoji = emojis[i]
            // A precise emoji match makes the English word redundant --
            // drop it unless the user asked to always show both.
            val elideGloss = emoji != null && !settings.emojiAlwaysShowBoth
            val gloss = if (elideGloss) null else glossResults[i].result?.text
            toSegment(token, settings, romanizer, gloss, emoji, glossResults[i].isPhraseContinuation)
        }
    }

    private fun toSegment(
        token: SurfaceReading,
        settings: JapanglifySettings,
        romanizer: Romanizer,
        gloss: String?,
        emoji: String?,
        isPhraseContinuation: Boolean = false
    ): AnnotatedSegment {
        val surface = token.surface

        // Punctuation / symbols: keep on base, map to Latin on the romaji line.
        // No dictionary entry makes sense here, so gloss is never attached.
        if (KanaConverter.isMostlyPunctuation(surface)) {
            val roma = if (settings.includeRomaji) {
                KanaConverter.punctuationToRomaji(surface).ifBlank { surface }
            } else null
            // Mirror punctuation on the furigana row so interlinear columns stay
            // furigana-style (ruby row carries the same mark above the base).
            val furi = if (settings.includeFurigana) surface else null
            return AnnotatedSegment(
                surface = surface,
                furigana = furi,
                romaji = roma,
                needsFurigana = false,
                isBoundToPrevious = token.isBoundToPrevious,
                isParticle = token.isParticle,
                emoji = emoji,
                isPhraseContinuation = isPhraseContinuation
            )
        }

        val hasKanji = KanaConverter.containsKanji(surface)
        val rawReading = token.reading
            ?.takeIf { KanaConverter.isValidReading(it) }
            ?.let { KanaConverter.toHiragana(it) }

        // Prefer provider reading; for pure kana use the surface itself.
        val readingHira: String? = when {
            rawReading != null -> rawReading
            KanaConverter.isMostlyKana(surface) ->
                KanaConverter.toHiragana(surface.filter {
                    KanaConverter.isKana(it) || it == 'ー'
                }).ifEmpty { null }
            else -> null
        }

        val needsFurigana = hasKanji && readingHira != null

        val furigana: String? = when {
            !settings.includeFurigana -> null
            needsFurigana -> readingHira
            // Optionally show furigana on kana-only spans (identity reading)
            !settings.furiganaKanjiOnly && readingHira != null &&
                KanaConverter.isMostlyKana(surface) -> readingHira
            else -> null
        }

        val romajiSource = readingHira
            ?: surface.takeIf { KanaConverter.isMostlyKana(it) }?.let {
                KanaConverter.toHiragana(it.filter { ch ->
                    KanaConverter.isKana(ch) || ch == 'ー'
                })
            }

        val romaji: String? = when {
            !settings.includeRomaji -> null
            romajiSource.isNullOrBlank() -> {
                // Surface may mix kana + punctuation (e.g. 「はい」)
                val stripped = surface.filter {
                    KanaConverter.isKana(it) || it == 'ー'
                }
                if (stripped.isNotEmpty()) {
                    val r = romanizer.romanize(KanaConverter.toHiragana(stripped))
                    capitalizeIf(settings, r)
                } else if (surface.any { KanaConverter.isPunctuation(it) }) {
                    KanaConverter.punctuationToRomaji(surface)
                } else if (surface.isNotBlank()) {
                    // Non-Japanese passthrough (e.g. "Wi-Fi", a brand name, a
                    // fullwidth-typed number): the romaji line should still
                    // carry it rather than leave a blank hole under it.
                    KanaConverter.fullwidthToHalfwidth(surface)
                } else null
            }
            else -> capitalizeIf(settings, romanizer.romanize(romajiSource))
        }

        // Mirrors [romaji] above using the mora-hyphenated romanizer instead —
        // see [AnnotatedSegment.romajiMora]. Punctuation-mapped/passthrough
        // branches have no mora structure, so they're left null there; the
        // renderer falls back to [romaji] whenever this is null.
        val romajiMora: String? = when {
            !settings.includeRomaji -> null
            romajiSource.isNullOrBlank() -> {
                val stripped = surface.filter { KanaConverter.isKana(it) || it == 'ー' }
                if (stripped.isNotEmpty()) {
                    capitalizeIf(settings, romanizer.romanizeMora(KanaConverter.toHiragana(stripped)))
                } else null
            }
            else -> capitalizeIf(settings, romanizer.romanizeMora(romajiSource))
        }

        return AnnotatedSegment(
            surface = surface,
            furigana = furigana,
            romaji = romaji,
            needsFurigana = needsFurigana,
            isBoundToPrevious = token.isBoundToPrevious,
            isParticle = token.isParticle,
            romajiMora = romajiMora,
            gloss = gloss,
            emoji = emoji,
            isPhraseContinuation = isPhraseContinuation
        )
    }

    private fun capitalizeIf(settings: JapanglifySettings, r: String): String =
        if (settings.capitalizeRomaji) r.replaceFirstChar {
            if (it.isLowerCase()) it.titlecase() else it.toString()
        } else r

    /**
     * Greedy character-class runs when no morphological analyzer is bound.
     * Good enough for pure kana and mixed Latin/punctuation; kanji runs
     * will lack readings until a [ReadingProvider] is supplied.
     */
    private fun fallbackTokenize(text: String): List<SurfaceReading> {
        if (text.isEmpty()) return emptyList()
        val result = ArrayList<SurfaceReading>()
        val buf = StringBuilder()
        var kind = kindOf(text[0])

        fun flush() {
            if (buf.isNotEmpty()) {
                val s = buf.toString()
                val reading = when (kind) {
                    Kind.KANA -> KanaConverter.toHiragana(s)
                    Kind.PUNCT -> s
                    else -> null
                }
                result += SurfaceReading(s, reading)
                buf.clear()
            }
        }

        for (c in text) {
            val k = kindOf(c)
            if (k != kind) {
                flush()
                kind = k
            }
            buf.append(c)
        }
        flush()
        return result
    }

    private enum class Kind { KANA, KANJI, PUNCT, OTHER }

    private fun kindOf(c: Char): Kind = when {
        KanaConverter.isKana(c) || c == 'ー' -> Kind.KANA
        KanaConverter.isKanji(c) -> Kind.KANJI
        KanaConverter.isPunctuation(c) -> Kind.PUNCT
        else -> Kind.OTHER
    }
}
