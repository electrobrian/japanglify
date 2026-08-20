package com.japanglify.app.domain.dictionary

import com.japanglify.app.domain.JapaneseAnalyzer
import com.japanglify.app.domain.JapanglifySettings.Companion.DEFAULT_MAX_GLOSS_LENGTH

/**
 * Looks up an English gloss for each token via its dictionary/base form.
 *
 * Takes the *whole* token list (not one token at a time) even though v1
 * never looks across token boundaries — this is the deliberate extension
 * point for a future phrasal-grouping pass (e.g. ~ている, ~てください
 * auxiliary chains) to become an internal change to [annotate]'s loop,
 * not a rearchitecture. See the plan's "Phrasal grouping" backlog note.
 */
class GlossAnnotator(private val dictionary: DictionaryProvider) {

    fun interface DictionaryProvider {
        /**
         * [reading] is the token's kana reading (katakana or hiragana; null
         * when unknown or when looking up a multi-token phrase). When present
         * it disambiguates same-spelling headwords read differently — e.g.
         * 僕 is read ぼく ("I, me") here, not しもべ ("servant") — so a
         * reading-aware provider restricts its candidate senses to the
         * matching reading before scoring.
         *
         * [verbPosHint] (see [jmdictVerbConjugationPrefix]) further
         * disambiguates same-reading, same-spelling-in-kana but otherwise
         * unrelated JMdict *words* that a reading match alone can't tell
         * apart — する ("to do") and 擦る ("to rub") are both read/spelled
         * する in kana, so a reading-only filter still pools both; Kuromoji's
         * own conjugation class for this specific token (サ変・スル vs.
         * 五段・ラ行) is the signal that tells them apart. Null when the
         * token isn't an ordinary verb conjugation, or when looking up a
         * multi-token phrase.
         *
         * [weights] drives [SenseSelector] when several candidate senses
         * remain after both filters.
         */
        fun lookup(baseForm: String, reading: String?, verbPosHint: String?, weights: SenseWeights): DictionaryEntry?
    }

    /**
     * [text] is the gloss text, direct with no abbreviation/metadata prefix
     * (e.g. just "paper", never "n. paper") -- found this reads as noise,
     * not help, live. [partOfSpeech] is the entry's real category and is
     * never shown in [text]; it exists purely for a consumer like
     * [com.japanglify.app.domain.emoji.EmojiAnnotator] that needs the actual
     * category to apply a part-of-speech scope filter.
     */
    data class GlossResult(val text: String, val partOfSpeech: PartOfSpeech?)

    /**
     * One entry per input token, same size/order as [tokens]. [result] null
     * means either no dictionary entry was found (a genuinely missing word,
     * or a Kuromoji/JMdict lexical mismatch; see the plan's open questions)
     * or a deliberately omitted gloss (every particle -- see [format] --
     * plus every [JapaneseAnalyzer.SurfaceReading.isBoundToPrevious] token,
     * plus every token past the first in a matched phrase span, see below).
     * [isPhraseContinuation] is true for exactly that last case: a token
     * absorbed into the *previous* token's multi-token phrase match, rather
     * than glossed (or left blank) on its own — the renderer uses this to
     * keep a phrase's tokens on one row even under a narrow line-wrap
     * budget, since a wrap landing mid-phrase would strand its gloss on one
     * row and its remaining kana on the next with no visible link between
     * them (found live: ご機嫇よう wrapped between ご and 機嫇).
     */
    data class TokenGloss(val result: GlossResult?, val isPhraseContinuation: Boolean = false)

    fun annotate(
        tokens: List<JapaneseAnalyzer.SurfaceReading>,
        senseWeights: SenseWeights = SenseSelectionPreset.MODERN.weights!!,
        maxGlossLength: Int = DEFAULT_MAX_GLOSS_LENGTH
    ): List<TokenGloss> {
        val results = arrayOfNulls<TokenGloss>(tokens.size)
        var i = 0
        while (i < tokens.size) {
            // Longest-match phrase first: several consecutive tokens whose
            // concatenated surface is itself a dictionary headword (a real set
            // expression, e.g. ご+機嫌+よう -> ご機嫌よう "nice to see you /
            // good day"). Kuromoji splits such phrases into their pieces, and
            // glossing the pieces separately is both wrong and noisy, so a
            // whole-phrase entry wins when one exists. The gloss rides on the
            // span's first token (like split-kanji/okurigana romaji does);
            // the rest are marked as phrase continuations (see [TokenGloss]).
            val phrase = longestPhraseMatch(tokens, i, senseWeights)
            if (phrase != null) {
                val (span, entry) = phrase
                results[i] = TokenGloss(format(entry, maxGlossLength)?.let { GlossResult(it, entry.partOfSpeech) })
                for (j in 1 until span) results[i + j] = TokenGloss(null, isPhraseContinuation = true)
                i += span
                continue
            }
            results[i] = TokenGloss(glossToken(tokens[i], senseWeights, maxGlossLength))
            i++
        }
        return results.map { it!! }
    }

    /**
     * The longest span of [MIN_PHRASE_TOKENS]..[MAX_PHRASE_TOKENS] tokens
     * starting at [start] whose concatenated surface is a dictionary
     * headword, or null if none is. A phrase has no single reading of its
     * own, so the lookup passes `reading = null` (no reading filter).
     */
    private fun longestPhraseMatch(
        tokens: List<JapaneseAnalyzer.SurfaceReading>,
        start: Int,
        weights: SenseWeights
    ): Pair<Int, DictionaryEntry>? {
        val maxSpan = minOf(MAX_PHRASE_TOKENS, tokens.size - start)
        for (span in maxSpan downTo MIN_PHRASE_TOKENS) {
            // Proper-noun metadata is contextual. Do not let a name become
            // part of a coincidentally matching JMdict expression simply
            // because the same characters can form a common-word phrase.
            if ((start until start + span).any { tokens[it].isProperNoun }) continue
            val surface = buildString {
                for (j in start until start + span) append(tokens[j].surface)
            }
            val entry = dictionary.lookup(surface, null, null, weights) ?: continue
            // Only accept the span as a real set phrase when the matched entry
            // is an expression or interjection. Without this gate a
            // coincidental concatenation that merely *spells* an ordinary word
            // hijacks the gloss — found live: いい ("good") + ん collides with
            // 医院 ("doctor's office"), turning a correct per-token gloss into a
            // wrong one — while the phrases we actually want (ご機嫌よう, これより,
            // よね) are exactly the exp/int entries this keeps.
            if (entry.partOfSpeech == PartOfSpeech.EXPRESSION ||
                entry.partOfSpeech == PartOfSpeech.INTERJECTION
            ) {
                return span to entry
            }
        }
        return null
    }

    private fun glossToken(
        token: JapaneseAnalyzer.SurfaceReading,
        weights: SenseWeights,
        maxGlossLength: Int
    ): GlossResult? {
        // IPADIC has already classified this token in context as a proper
        // noun. JMdict's common-word lookup is intentionally context-free,
        // so it can otherwise attach an implausible English gloss (and then
        // an emoji) to somebody's name. Keep the reading/romaji untouched;
        // only skip semantic annotation. Unknown or ambiguous spellings stay
        // conservative because this flag is false unless the provider says so.
        if (token.isProperNoun) return null
        // A conjugation ending / auxiliary / copula (ました, ない, だ, ...)
        // isn't an independent word -- it completes the previous token's
        // inflected form (see isBoundToPrevious's own doc). Glossing it
        // separately reads as a stray, disconnected word, and JMdict's
        // POS code for these doesn't reliably land on PARTICLE either
        // (copula is its own JMdict tag, "cop", which format()'s
        // PARTICLE-only check never catches) -- found live via real
        // device UAT: だ's own gloss rendered as an unrelated word
        // jammed with zero gap right against the previous word's gloss
        // (isBoundToPrevious cells get no word-gap by design), reading
        // as one garbled word, e.g. "wonderfuldui" for 不思議な. Skipping
        // the lookup entirely for these tokens fixes both problems at
        // once: no stray gloss, and nothing left to jam into the gap.
        if (token.isBoundToPrevious) return null
        // Prefer Kuromoji's own contextual particle tag over re-deriving
        // it from the dictionary lookup below: a dictionary match is
        // keyed on baseForm/surface alone, out of context, and can land
        // on the wrong same-spelling headword (a real risk for common
        // single-kana particles) -- Kuromoji already knows definitively
        // whether *this* token, in *this* sentence, is a particle.
        // format()'s own entry.partOfSpeech check stays as a second,
        // independent safety net for a ReadingProvider that doesn't set
        // this flag.
        if (token.isParticle) return null
        val key = token.baseForm ?: token.surface
        // Pass the token's reading and verb-conjugation hint so the provider
        // can disambiguate a same-spelling headword read two ways, or a
        // same-reading spelling shared by unrelated words (see
        // DictionaryProvider.lookup).
        val entry = dictionary.lookup(key, token.reading, token.verbPosHint, weights) ?: return null
        return format(entry, maxGlossLength)?.let { GlossResult(it, entry.partOfSpeech) }
    }

    private fun format(entry: DictionaryEntry, maxGlossLength: Int): String? {
        // Every particle is omitted, not just the abstract-marker subset
        // (は/が/を) an earlier version of this curated by hand. Found live
        // via real device UAT: の's actual JMdict gloss ("possessive /
        // nominalizing particle" plus, for some entries, a much longer
        // explanatory definition) reads as an entire sentence crammed into
        // one word's slot -- unusable regardless of whether の counts as
        // "abstract" or "concrete." A JMdict gloss is written for a
        // dictionary entry, not for a one-line annotation under a single
        // character, and that mismatch isn't particular to a handful of
        // grammatical-role markers -- it affects particles generally, so
        // the whole category is omitted rather than trying to hand-curate
        // which particles' dictionary glosses happen to be short enough.
        if (entry.partOfSpeech == PartOfSpeech.PARTICLE) return null
        // No "n."/"v."/etc. prefix -- a direct translation, not a dictionary
        // entry with lexicographic metadata attached. Tried showing it only
        // when a headword's senses genuinely disagreed on part of speech;
        // still read as unwanted commentary rather than help, per direct
        // feedback, so it's gone unconditionally rather than narrowed further.
        // Same reasoning for JMdict's own "to " infinitive-marker convention
        // on verb glosses ("to see", "to become") -- it's a citation-form
        // artifact of how JMdict writes verb entries, not information: 見る
        // means "see," full stop, and marking that as an infinitive adds
        // nothing a reader uses. Gated on VERB specifically, not applied to
        // every gloss: an expression/adverb gloss can legitimately start
        // with "to " as real content ("to a certain extent," "to no end"),
        // where stripping it would corrupt the meaning rather than
        // declutter it -- only a verb's leading "to " is purely a citation-
        // form marker with nothing lost by removing it.
        val gloss = if (entry.partOfSpeech == PartOfSpeech.VERB) entry.gloss.removePrefix("to ") else entry.gloss
        return trimGlossToLength(gloss, maxGlossLength)
    }

    /**
     * Keeps adding whole '/'-joined synonyms (DictionaryDownloadManager
     * stores up to `MAX_GLOSSES_PER_SENSE` of them) while the running total
     * fits [maxGlossLength], stopping at the first one that would overflow
     * it. The very first synonym is always kept in full even if it alone
     * exceeds the budget -- never truncated mid-word -- so this only ever
     * drops whole trailing synonyms, never mangles one.
     *
     * A length budget rather than a fixed synonym *count* is what lets a
     * short, genuinely distinguishing set like さん's "Mr/Mrs/Miss" survive
     * untouched (11 chars, comfortably under [JapanglifySettings.DEFAULT_MAX_GLOSS_LENGTH])
     * while a long same-meaning chain like "do/to carry out/to perform" or
     * ご機嫌よう's "nice to see you/good morning/good evening" trims down on
     * its own -- an earlier version of this hard-coded "just the first
     * synonym" for interjections/expressions specifically (their synonyms
     * tend to be pure register variants of one greeting) and left every
     * other part of speech's full set untouched, which is exactly the
     * category-by-category guessing this length-based approach replaces:
     * found live that verbs/nouns/adjectives (never gated by that rule)
     * could carry equally long near-duplicate synonym lists of their own,
     * each one stretching that word's whole interlinear column to fit the
     * English gloss underneath it (see [JapanglifySettings.maxGlossLength]).
     */
    private fun trimGlossToLength(gloss: String, maxGlossLength: Int): String {
        val synonyms = gloss.split("/")
        var kept = synonyms.first()
        for (synonym in synonyms.drop(1)) {
            val candidate = "$kept/$synonym"
            if (candidate.length > maxGlossLength) break
            kept = candidate
        }
        return kept
    }

    private companion object {
        /** Phrase lookup only kicks in for multi-token spans. */
        const val MIN_PHRASE_TOKENS = 2
        /**
         * Longest span the greedy phrase pass will try to match as one
         * dictionary entry. 4 comfortably covers set expressions like
         * ご機嫌よう (3 tokens) without turning every lookup into a long chain
         * of speculative DB queries on a big paste.
         */
        const val MAX_PHRASE_TOKENS = 4
    }
}
