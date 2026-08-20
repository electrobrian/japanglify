package com.japanglify.app.domain

import com.atilika.kuromoji.ipadic.Token
import com.atilika.kuromoji.ipadic.Tokenizer
import com.japanglify.app.domain.dictionary.jmdictVerbConjugationPrefix

/**
 * Kuromoji/IPADIC-backed [JapaneseAnalyzer.ReadingProvider].
 * Tokenizer construction loads the dictionary once; keep a single instance
 * per process (see `JapanglifyApp` in the app module).
 *
 * Lives in the pure-JVM `domain` module (Kuromoji is a JVM library, not an
 * Android dependency) precisely so it is the ONE provider both the Android
 * app and [DemoMain]/the JVM unit tests use. An earlier copy lived in the
 * app module with its own logic while [DemoMain] built a second, simpler
 * inline provider that skipped number-merging and never set
 * [JapaneseAnalyzer.SurfaceReading.isParticle]/`isBoundToPrevious` -- so
 * terminal/`:domain:runDemo` output silently diverged from the device, and
 * a JVM test could pass while the same input rendered wrong on-device
 * (found live: 七 kept its reading in the demo but lost it on the device).
 * A single shared provider makes the terminal a faithful mirror of the app.
 *
 * Particle spellings that differ from surface kana in speech
 * (は→わ, へ→え, を→お) are normalized here so romaji matches speech.
 */
class KuromojiReadingProvider(
    private val tokenizer: Tokenizer = Tokenizer.Builder().build()
) : JapaneseAnalyzer.ReadingProvider {

    override fun tokenize(text: String): List<JapaneseAnalyzer.SurfaceReading> {
        if (text.isEmpty()) return emptyList()
        return mergeConsecutiveNumbers(tokenizer.tokenize(text)).map { token ->
            JapaneseAnalyzer.SurfaceReading(
                surface = token.surface,
                reading = spokenReading(token),
                // 助動詞 (auxiliary verb / conjugation ending, e.g. ました, ない)
                // completes the previous word rather than starting a new one.
                isBoundToPrevious = token.partOfSpeechLevel1 == "助動詞",
                isParticle = token.partOfSpeechLevel1 == "助詞",
                isProperNoun = token.partOfSpeechLevel1 == "名詞" && token.partOfSpeechLevel2 == "固有名詞",
                baseForm = token.baseForm,
                verbPosHint = jmdictVerbConjugationPrefix(token.conjugationType)
            )
        }
    }

    /**
     * IPADIC tokenizes multi-digit numbers one digit per token (名詞,数) —
     * "２５" comes back as "２" and "５" separately, with no reading on
     * either. Left alone this fragments a single number into multiple
     * interlinear cells (each getting its own word-gap/no-gap treatment
     * inconsistently) instead of the one column a number should occupy.
     * Kuromoji's [Token] has no public constructor, so we merge via a small
     * shim rather than building a synthetic Token.
     */
    private data class MergedToken(
        val surface: String,
        val rawReading: String?,
        val partOfSpeechLevel1: String,
        val partOfSpeechLevel2: String,
        val baseForm: String?,
        val conjugationType: String?
    )

    private fun mergeConsecutiveNumbers(tokens: List<Token>): List<MergedToken> {
        val out = ArrayList<MergedToken>()
        var i = 0
        while (i < tokens.size) {
            val t = tokens[i]
            if (t.partOfSpeechLevel2 == "数") {
                val surface = StringBuilder(t.surface)
                var j = i + 1
                while (j < tokens.size && tokens[j].partOfSpeechLevel2 == "数") {
                    surface.append(tokens[j].surface)
                    j++
                }
                // A GENUINE merge (2+ digit tokens, e.g. multi-digit Arabic
                // numerals like "２５" tokenized one digit at a time) has no
                // single dictionary reading, base form, or conjugation of
                // its own. A lone "数" token is a different case entirely --
                // 名詞,数 also tags standalone kanji numerals (七, 八, ...),
                // which DO carry a real Kuromoji reading the same as any
                // other single token; nulling it out unconditionally here
                // silently dropped it. Found live: 七 lost its なな reading
                // this way, leaving it with no furigana and its romaji
                // falling back to the raw kanji glyph.
                val merged = j > i + 1
                out += MergedToken(
                    surface = surface.toString(),
                    rawReading = if (merged) null else t.reading,
                    partOfSpeechLevel1 = t.partOfSpeechLevel1,
                    partOfSpeechLevel2 = t.partOfSpeechLevel2,
                    baseForm = if (merged) null else t.baseForm,
                    conjugationType = if (merged) null else t.conjugationType
                )
                i = j
            } else {
                out += MergedToken(t.surface, t.reading, t.partOfSpeechLevel1, t.partOfSpeechLevel2, t.baseForm, t.conjugationType)
                i++
            }
        }
        return out
    }

    private fun spokenReading(token: MergedToken): String? {
        val surface = token.surface
        val pos1 = token.partOfSpeechLevel1
        // 助詞 with historical kana spellings spoken differently
        if (pos1 == "助詞") {
            when (surface) {
                "は" -> return "ワ"
                "へ" -> return "エ"
                "を" -> return "オ"
            }
        }
        return token.rawReading?.takeIf { it.isNotBlank() && it != "*" }
    }
}
