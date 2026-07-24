//
//  FeatureSearch.swift
//  MacTweak
//
//  Offline "semantic" search over the feature catalog — a faithful port of
//  CodeDraft's DraftSearch ensemble, trimmed for a small static corpus (no file
//  cache / mtime / snippet machinery needed here). Apple's NaturalLanguage
//  framework provides lemmatisation so word forms match (battery ↔ batteries,
//  disable ↔ disabled); trigram overlap + Damerau-Levenshtein add typo
//  tolerance (frewall → firewall); subword splitting handles keys like
//  "hosts-adblock" and "disable-ipv6". Fully offline, zero external deps.
//
//  Scoring constants and tier weights match the DraftSearch reference exactly:
//  Exact 1.0 · Prefix 0.9 · Stem 0.8 · Typo 0.75 · Trigram 0.7×overlap,
//  title boost ×1.15, phrase bonus +0.2, whole-title bonus +0.5, floor 0.45.
//

import Foundation
import NaturalLanguage

// MARK: - Tokeniser

private enum SearchTokenizer {

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive], locale: .current).lowercased()
    }

    /// Tokenise, then subword-split each token on camelCase humps and the
    /// separators `_ . / : -`, emitting both the whole token and each part.
    static func tokens(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result = Set<String>()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            for part in subwordParts(of: String(text[range])) {
                let n = normalize(part)
                if !n.isEmpty { result.insert(n) }
            }
            return true
        }
        return Array(result)
    }

    /// Lemma of a natural-language word (letters-only, ≥3 chars); else the token.
    static func stem(_ token: String) -> String {
        guard token.count >= 3,
              token.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) })
        else { return token }
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = token
        let (tag, _) = tagger.tag(at: token.startIndex, unit: .word, scheme: .lemma)
        if let lemma = tag?.rawValue, !lemma.isEmpty { return lemma.lowercased() }
        return token
    }

    static func trigrams(of token: String) -> Set<String> {
        let chars = Array(token)
        guard chars.count >= 3 else { return [token] }
        var result = Set<String>(minimumCapacity: chars.count - 2)
        for i in 0...(chars.count - 3) { result.insert(String(chars[i..<(i + 3)])) }
        return result
    }

    /// |a ∩ b| / min(|a|, |b|) — right metric when the query is shorter.
    static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(min(a.count, b.count))
    }

    /// Within Damerau-Levenshtein distance 1 (tokens ≥4 chars, length diff ≤1).
    static func isTypoNeighbor(_ a: String, _ b: String) -> Bool {
        guard a != b else { return false }
        let s = Array(a), t = Array(b)
        guard s.count >= 4, abs(s.count - t.count) <= 1 else { return false }
        return isWithinEditDistanceOne(s, t)
    }

    private static func isWithinEditDistanceOne(_ s: [Character], _ t: [Character]) -> Bool {
        if s.count == t.count {
            var mismatches: [Int] = []
            for i in 0..<s.count where s[i] != t[i] {
                mismatches.append(i)
                if mismatches.count > 2 { return false }
            }
            switch mismatches.count {
            case 1: return true
            case 2:
                let (i, j) = (mismatches[0], mismatches[1])
                return j == i + 1 && s[i] == t[j] && s[j] == t[i]
            default: return false
            }
        }
        let (longer, shorter) = s.count > t.count ? (s, t) : (t, s)
        var i = 0, j = 0, skipped = false
        while i < longer.count, j < shorter.count {
            if longer[i] == shorter[j] { i += 1; j += 1 }
            else { if skipped { return false }; skipped = true; i += 1 }
        }
        return true
    }

    private static func subwordParts(of raw: String) -> [String] {
        var parts: [String] = [raw]
        let sep = CharacterSet(charactersIn: "_./:-")
        let sepParts = raw.components(separatedBy: sep).filter { !$0.isEmpty }
        if sepParts.count > 1 { parts.append(contentsOf: sepParts) }

        let camel = try? NSRegularExpression(
            pattern: "(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])")
        for part in (sepParts.isEmpty ? [raw] : sepParts) {
            guard let camel else { continue }
            let ns = part as NSString
            let boundaries = camel.matches(in: part, range: NSRange(location: 0, length: ns.length))
                .map { $0.range.location }
            guard !boundaries.isEmpty else { continue }
            let positions = [0] + boundaries + [part.count]
            for i in 0..<(positions.count - 1) {
                let start = part.index(part.startIndex, offsetBy: positions[i])
                let end   = part.index(part.startIndex, offsetBy: positions[i + 1])
                let sub = String(part[start..<end])
                if !sub.isEmpty { parts.append(sub) }
            }
        }
        return parts
    }
}

// MARK: - Engine

/// One searchable feature: a stable id, its title, and the rest of its text
/// (summary, category, tags, gains, key…). Title and body are kept apart so a
/// title hit can be boosted over a body-only hit.
struct SearchableItem: Identifiable {
    let id: String
    let title: String
    let body: String
}

/// Ranks `SearchableItem`s against a free-text query using the DraftSearch
/// ensemble. Per-item token indexes are built once and cached by id (the
/// catalog is static), so each keystroke only tokenises the short query.
final class FeatureSearchEngine {

    private static let exactWeight:   Double = 1.0
    private static let prefixWeight:  Double = 0.9
    private static let stemWeight:    Double = 0.8
    private static let typoWeight:    Double = 0.75
    private static let trigramWeight: Double = 0.7
    private static let trigramGate:   Double = 0.5
    private static let scoreFloor:    Double = 0.45
    private static let titleBoost:    Double = 1.15
    private static let phraseBonus:   Double = 0.2
    private static let titleExactBonus: Double = 0.5
    private static let prefixMinLength: Int = 3

    private struct TokenIndex {
        let tokens: Set<String>
        let stems: Set<String>
        let trigramMap: [String: Set<String>]
        let trigramSuperset: Set<String>
    }
    private struct Doc {
        let title: TokenIndex
        let body: TokenIndex
        let normTitle: String
        let normBody: String
    }

    private var cache: [String: Doc] = [:]

    /// Ranked ids of items scoring above the floor, best first.
    func rank(_ query: String, items: [SearchableItem]) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items.map(\.id) }

        let queryTokens = SearchTokenizer.tokens(in: q)
        guard !queryTokens.isEmpty else { return [] }
        let normQuery = SearchTokenizer.normalize(q)

        let queryData: [(token: String, stem: String, trigrams: Set<String>)] =
            queryTokens.map { ($0, SearchTokenizer.stem($0), SearchTokenizer.trigrams(of: $0)) }
        let querySuperset = queryData.reduce(into: Set<String>()) { $0.formUnion($1.trigrams) }

        var scored: [(id: String, score: Double)] = []
        for item in items {
            let doc = document(for: item)

            // Trigram prefilter: skip items whose superset is disjoint from the query.
            let superset = doc.title.trigramSuperset.union(doc.body.trigramSuperset)
            guard !superset.isDisjoint(with: querySuperset) else { continue }

            var tokenScores: [Double] = []
            var bestToken: String?
            var bestScore = 0.0
            for qd in queryData {
                let (score, token) = Self.scoreQueryToken(qd, title: doc.title, body: doc.body)
                tokenScores.append(score)
                if score > bestScore { bestScore = score; bestToken = token }
            }
            let mean = tokenScores.isEmpty ? 0 : tokenScores.reduce(0, +) / Double(tokenScores.count)
            guard mean > 0 else { continue }

            let inTitle = bestToken.map {
                doc.title.tokens.contains($0) || doc.title.stems.contains(SearchTokenizer.stem($0))
            } ?? false
            var finalScore = inTitle ? mean * Self.titleBoost : mean

            if doc.normTitle.contains(normQuery) || doc.normBody.contains(normQuery) {
                finalScore += Self.phraseBonus
            }
            if doc.normTitle == normQuery { finalScore += Self.titleExactBonus }

            guard finalScore >= Self.scoreFloor else { continue }
            scored.append((item.id, finalScore))
        }

        scored.sort { $0.score > $1.score }
        return scored.map(\.id)
    }

    private func document(for item: SearchableItem) -> Doc {
        if let cached = cache[item.id] { return cached }
        let doc = Doc(
            title: Self.buildIndex(SearchTokenizer.normalize(item.title)),
            body: Self.buildIndex(SearchTokenizer.normalize(item.body)),
            normTitle: SearchTokenizer.normalize(item.title),
            normBody: SearchTokenizer.normalize(item.body)
        )
        cache[item.id] = doc
        return doc
    }

    private static func scoreQueryToken(
        _ qd: (token: String, stem: String, trigrams: Set<String>),
        title: TokenIndex, body: TokenIndex
    ) -> (score: Double, token: String?) {
        var best = 0.0
        var bestToken: String?
        func consider(_ score: Double, _ token: String) {
            if score > best { best = score; bestToken = token }
        }
        for idx in [title, body] {
            if idx.tokens.contains(qd.token) { consider(exactWeight, qd.token); continue }
            if qd.token.count >= prefixMinLength {
                for t in idx.tokens where t.hasPrefix(qd.token) { consider(prefixWeight, t) }
            }
            if idx.stems.contains(qd.stem) {
                let rep = idx.tokens.first { SearchTokenizer.stem($0) == qd.stem } ?? qd.stem
                consider(stemWeight, rep)
            }
            for (t, grams) in idx.trigramMap {
                let ov = SearchTokenizer.overlap(qd.trigrams, grams)
                if ov >= trigramGate { consider(trigramWeight * ov, t) }
                if ov >= 0.3, SearchTokenizer.isTypoNeighbor(qd.token, t) { consider(typoWeight, t) }
            }
        }
        return (best, bestToken)
    }

    private static func buildIndex(_ text: String) -> TokenIndex {
        let list = SearchTokenizer.tokens(in: text)
        let tokenSet = Set(list)
        var trigramMap = [String: Set<String>](minimumCapacity: tokenSet.count)
        for t in tokenSet { trigramMap[t] = SearchTokenizer.trigrams(of: t) }
        let superset = trigramMap.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        return TokenIndex(tokens: tokenSet,
                          stems: Set(list.map { SearchTokenizer.stem($0) }),
                          trigramMap: trigramMap,
                          trigramSuperset: superset)
    }
}
