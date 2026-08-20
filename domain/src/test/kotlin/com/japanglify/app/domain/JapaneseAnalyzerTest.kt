package com.japanglify.app.domain

import com.japanglify.app.domain.dictionary.DictionaryEntry
import com.japanglify.app.domain.dictionary.GlossAnnotator
import com.japanglify.app.domain.dictionary.PartOfSpeech
import com.japanglify.app.domain.emoji.EmojiAnnotator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
// OutputFormat used in engine end-to-end tests

class JapaneseAnalyzerTest {

    @Test
    fun pureKanaGetsRomaji() {
        val analyzer = JapaneseAnalyzer(readingProvider = null)
        val segments = analyzer.annotate(
            "こんにちは",
            JapanglifySettings(furiganaKanjiOnly = true)
        )
        assertEquals(1, segments.size)
        assertEquals("こんにちは", segments[0].surface)
        assertEquals("konnichiha", segments[0].romaji)
        // Kanji-only furigana: pure kana should not get identity furigana
        assertFalse(segments[0].hasFurigana)
    }

    @Test
    fun kanjiUsesReadingProvider() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(
                JapaneseAnalyzer.SurfaceReading("日本語", "ニホンゴ"),
                JapaneseAnalyzer.SurfaceReading("を", "ヲ"),
                JapaneseAnalyzer.SurfaceReading("勉強", "ベンキョウ"),
                JapaneseAnalyzer.SurfaceReading("する", "スル")
            )
        }
        val analyzer = JapaneseAnalyzer(provider)
        val segments = analyzer.annotate("日本語を勉強する", JapanglifySettings())

        val nihongo = segments.first { it.surface == "日本語" }
        assertEquals("にほんご", nihongo.furigana)
        assertEquals("nihongo", nihongo.romaji)
        assertTrue(nihongo.needsFurigana)

        val benkyou = segments.first { it.surface == "勉強" }
        assertEquals("べんきょう", benkyou.furigana)
        assertTrue(benkyou.romaji!!.startsWith("benky"))
    }

    @Test
    fun glossesOffByDefaultEvenWithAnnotatorPresent() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(JapaneseAnalyzer.SurfaceReading("紙", "かみ", baseForm = "紙"))
        }
        val annotator = GlossAnnotator(
            GlossAnnotator.DictionaryProvider { _, _, _, _ ->
                DictionaryEntry("紙", "かみ", PartOfSpeech.NOUN, "paper")
            }
        )
        val analyzer = JapaneseAnalyzer(provider, annotator)
        // includeGlosses defaults to false — the annotator must never be
        // consulted, mirroring how furigana/romaji providers degrade.
        val segments = analyzer.annotate("紙", JapanglifySettings())
        assertNull(segments[0].gloss)
        assertFalse(segments[0].hasGloss)
    }

    @Test
    fun glossesPopulatedWhenEnabled() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(JapaneseAnalyzer.SurfaceReading("紙", "かみ", baseForm = "紙"))
        }
        val annotator = GlossAnnotator(
            GlossAnnotator.DictionaryProvider { _, _, _, _ ->
                DictionaryEntry("紙", "かみ", PartOfSpeech.NOUN, "paper")
            }
        )
        val analyzer = JapaneseAnalyzer(provider, annotator)
        val segments = analyzer.annotate("紙", JapanglifySettings(includeGlosses = true))
        assertEquals("paper", segments[0].gloss)
        assertTrue(segments[0].hasGloss)
    }

    @Test
    fun glossesEnabledButNoAnnotatorDegradesGracefully() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(JapaneseAnalyzer.SurfaceReading("紙", "かみ", baseForm = "紙"))
        }
        // No dictionary downloaded yet — analyzer must not crash.
        val analyzer = JapaneseAnalyzer(provider, glossAnnotator = null)
        val segments = analyzer.annotate("紙", JapanglifySettings(includeGlosses = true))
        assertNull(segments[0].gloss)
    }

    private fun paperAnalyzer(emojiAnnotator: EmojiAnnotator?): JapaneseAnalyzer {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(JapaneseAnalyzer.SurfaceReading("紙", "かみ", baseForm = "紙"))
        }
        val glossAnnotator = GlossAnnotator(
            GlossAnnotator.DictionaryProvider { _, _, _, _ -> DictionaryEntry("紙", "かみ", PartOfSpeech.NOUN, "paper") }
        )
        return JapaneseAnalyzer(provider, glossAnnotator, emojiAnnotator)
    }

    @Test
    fun emojiOffByDefaultEvenWithAnnotatorPresent() {
        val emojiAnnotator = EmojiAnnotator(EmojiAnnotator.EmojiProvider { _, _ -> "📄" })
        val analyzer = paperAnalyzer(emojiAnnotator)
        val segments = analyzer.annotate("紙", JapanglifySettings(includeGlosses = true))
        assertNull(segments[0].emoji)
        assertEquals("paper", segments[0].gloss)
    }

    @Test
    fun preciseEmojiMatchElidesGlossByDefault() {
        val emojiAnnotator = EmojiAnnotator(EmojiAnnotator.EmojiProvider { _, _ -> "📄" })
        val analyzer = paperAnalyzer(emojiAnnotator)
        val segments = analyzer.annotate(
            "紙",
            JapanglifySettings(includeGlosses = true, includeEmoji = true)
        )
        assertEquals("📄", segments[0].emoji)
        assertNull(segments[0].gloss)
    }

    @Test
    fun alwaysShowBothKeepsGlossAlongsideEmoji() {
        val emojiAnnotator = EmojiAnnotator(EmojiAnnotator.EmojiProvider { _, _ -> "📄" })
        val analyzer = paperAnalyzer(emojiAnnotator)
        val segments = analyzer.annotate(
            "紙",
            JapanglifySettings(includeGlosses = true, includeEmoji = true, emojiAlwaysShowBoth = true)
        )
        assertEquals("📄", segments[0].emoji)
        assertEquals("paper", segments[0].gloss)
    }

    @Test
    fun posScopeExcludingNounDropsEmojiButKeepsGloss() {
        val emojiAnnotator = EmojiAnnotator(EmojiAnnotator.EmojiProvider { _, _ -> "📄" })
        val analyzer = paperAnalyzer(emojiAnnotator)
        val segments = analyzer.annotate(
            "紙",
            JapanglifySettings(
                includeGlosses = true,
                includeEmoji = true,
                emojiPosScope = setOf(PartOfSpeech.VERB)
            )
        )
        assertNull(segments[0].emoji)
        assertEquals("paper", segments[0].gloss)
    }

    @Test
    fun providerConfirmedProperNounKeepsReadingButSuppressesGlossAndEmoji() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(
                JapaneseAnalyzer.SurfaceReading(
                    surface = "太郎",
                    reading = "タロウ",
                    baseForm = "太郎",
                    isProperNoun = true
                )
            )
        }
        val glossAnnotator = GlossAnnotator(
            GlossAnnotator.DictionaryProvider { _, _, _, _ ->
                DictionaryEntry("太郎", "たろう", PartOfSpeech.NOUN, "eldest son")
            }
        )
        val emojiAnnotator = EmojiAnnotator(EmojiAnnotator.EmojiProvider { _, _ -> "👦" })
        val segment = JapaneseAnalyzer(provider, glossAnnotator, emojiAnnotator).annotate(
            "太郎",
            JapanglifySettings(includeGlosses = true, includeEmoji = true)
        ).single()

        assertEquals("たろう", segment.furigana)
        assertEquals("tarou", segment.romaji)
        assertNull(segment.gloss)
        assertNull(segment.emoji)
    }

    @Test
    fun ordinaryNounStillReceivesGlossAndEmojiWhenNotMarkedProper() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(JapaneseAnalyzer.SurfaceReading("紙", "カミ", baseForm = "紙"))
        }
        val glossAnnotator = GlossAnnotator(
            GlossAnnotator.DictionaryProvider { _, _, _, _ ->
                DictionaryEntry("紙", "かみ", PartOfSpeech.NOUN, "paper")
            }
        )
        val emojiAnnotator = EmojiAnnotator(EmojiAnnotator.EmojiProvider { _, _ -> "📄" })
        val segment = JapaneseAnalyzer(provider, glossAnnotator, emojiAnnotator).annotate(
            "紙",
            JapanglifySettings(includeGlosses = true, includeEmoji = true, emojiAlwaysShowBoth = true)
        ).single()

        assertEquals("paper", segment.gloss)
        assertEquals("📄", segment.emoji)
    }

    @Test
    fun kuromojiMarksCommonJapanesePersonalNameTokensAsProperNouns() {
        val tokens = KuromojiReadingProvider().tokenize("山田太郎")
        assertTrue(tokens.any { it.surface == "山田" && it.isProperNoun })
        assertTrue(tokens.any { it.surface == "太郎" && it.isProperNoun })
    }

    @Test
    fun emojiEnabledButNoAnnotatorDegradesGracefully() {
        val analyzer = paperAnalyzer(emojiAnnotator = null)
        val segments = analyzer.annotate(
            "紙",
            JapanglifySettings(includeGlosses = true, includeEmoji = true)
        )
        assertNull(segments[0].emoji)
        assertEquals("paper", segments[0].gloss)
    }

    @Test
    fun engineEndToEndParenthetical() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(JapaneseAnalyzer.SurfaceReading("漢字", "カンジ"))
        }
        val engine = JapanglifyEngine(JapaneseAnalyzer(provider))
        val out = engine.expand(
            "漢字",
            JapanglifySettings(outputFormat = OutputFormat.PARENTHETICAL)
        )
        assertEquals("漢字（かんじ / kanji）", out)
    }

    @Test
    fun engineEndToEndFuriganaInline() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(JapaneseAnalyzer.SurfaceReading("漢字", "カンジ"))
        }
        val engine = JapanglifyEngine(JapaneseAnalyzer(provider))
        val out = engine.expand(
            "漢字",
            JapanglifySettings(outputFormat = OutputFormat.FURIGANA_INLINE)
        )
        assertTrue(out.startsWith("漢字《かんじ》"))
        assertTrue(out.contains("kanji"))
    }

    @Test
    fun kunreiSystemPropagates() {
        val provider = JapaneseAnalyzer.ReadingProvider {
            listOf(JapaneseAnalyzer.SurfaceReading("必要", "ヒツヨウ"))
        }
        val engine = JapanglifyEngine(JapaneseAnalyzer(provider))
        val out = engine.expand(
            "必要",
            JapanglifySettings(
                romanizationSystem = RomanizationSystem.KUNREI,
                outputFormat = OutputFormat.PARENTHETICAL
            )
        )
        // ひつよう → hituyou in Kunrei (tu not tsu)
        assertTrue(out.contains("hituyou") || out.contains("hitsuyou"))
        assertTrue(out.contains("ひつよう"))
    }
}
