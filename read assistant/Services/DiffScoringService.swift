import Foundation

// MARK: - Diff Scoring Service
/// Implements text comparison using CFStringTokenizer-based Chinese word
/// segmentation with LCS diff, producing semantically meaningful comparisons.
final class DiffScoringService: ScoringServiceProtocol {

    // MARK: - ScoringServiceProtocol

    func compare(expected: String, actual: String) -> DiffResult {
        let normalizedExpected = normalizeText(expected)
        let normalizedActual = normalizeText(actual)

        // Semantic word-level tokenization (Chinese-aware)
        let rawExpected = tokenize(normalizedExpected)
        let rawActual = tokenize(normalizedActual)

        // Align token granularity: when CFStringTokenizer splits the same
        // compound word differently (e.g. "必备" vs "必"+"背"), split
        // unmatched multi-char tokens so LCS can match character-by-character.
        let (expectedTokens, actualTokens) = alignTokenGranularity(
            expectedTokens: rawExpected,
            actualTokens: rawActual
        )

        let differences = computeDifferences(
            expectedTokens: expectedTokens,
            actualTokens: actualTokens
        )
        let score = calculateScore(
            differences: differences,
            expectedCount: expectedTokens.count,
            actualCount: actualTokens.count
        )

        return DiffResult(
            differences: differences,
            score: score,
            expectedText: expected,
            actualText: actual
        )
    }

    func aggregateScore(from results: [DiffResult]) -> Double {
        guard !results.isEmpty else { return 0.0 }
        let total = results.reduce(0.0) { $0 + $1.score }
        return total / Double(results.count)
    }

    // MARK: - Text Normalization
    /// Normalizes text for comparison: removes whitespace and normalizes
    /// Chinese punctuation to ASCII equivalents for fairer comparison.
    private func normalizeText(_ text: String) -> String {
        var result = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        // Normalize common Chinese punctuation to ASCII
        result = result.replacingOccurrences(of: "，", with: ",")
        result = result.replacingOccurrences(of: "。", with: ".")
        result = result.replacingOccurrences(of: "；", with: ";")
        result = result.replacingOccurrences(of: "：", with: ":")
        result = result.replacingOccurrences(of: "？", with: "?")
        result = result.replacingOccurrences(of: "！", with: "!")
        result = result.replacingOccurrences(of: "\u{201c}", with: "\"")
        result = result.replacingOccurrences(of: "\u{201d}", with: "\"")
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")
        result = result.replacingOccurrences(of: "（", with: "(")
        result = result.replacingOccurrences(of: "）", with: ")")

        return result
    }

    // MARK: - Chinese Word Tokenization (CFStringTokenizer)
    /// Tokenizes text into semantic words using the system's built-in
    /// CFStringTokenizer with Chinese locale. Falls back to character-level
    /// splitting if tokenization produces no tokens.
    private func tokenize(_ text: String) -> [String] {
        let nsText = text as NSString
        let range = CFRange(location: 0, length: nsText.length)
        let locale = NSLocale(localeIdentifier: "zh_CN")
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            text as CFString,
            range,
            kCFStringTokenizerUnitWord,
            locale
        ) else {
            return text.map { String($0) }
        }

        var tokens: [String] = []
        var tokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0)
        while tokenType != CFStringTokenizerTokenType() {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if tokenRange.length > 0 {
                let token = nsText.substring(with: NSMakeRange(tokenRange.location, tokenRange.length))
                tokens.append(token)
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        // Fallback: if tokenizer produced nothing, split by character
        if tokens.isEmpty {
            return text.map { String($0) }
        }
        return tokens
    }

    // MARK: - Token Granularity Alignment
    /// Splits multi-character tokens that have no exact match on the other side.
    /// This fixes CFStringTokenizer inconsistencies: when "必备" appears as one
    /// token in actual but as ["必","背"] in expected, splitting "必备" → ["必","备"]
    /// lets LCS match character-by-character, and homophone detection then handles "背"↔"备".
    private func alignTokenGranularity(
        expectedTokens: [String],
        actualTokens: [String]
    ) -> ([String], [String]) {
        let expectedSet = Set(expectedTokens)
        let actualSet = Set(actualTokens)

        let alignedExpected = expectedTokens.flatMap { token -> [String] in
            if token.count > 1 && !actualSet.contains(token) {
                return token.map { String($0) }
            }
            return [token]
        }

        let alignedActual = actualTokens.flatMap { token -> [String] in
            if token.count > 1 && !expectedSet.contains(token) {
                return token.map { String($0) }
            }
            return [token]
        }

        return (alignedExpected, alignedActual)
    }

    // MARK: - Word-Level Diff Algorithm
    /// Computes word-level differences using LCS at the token granularity.
    /// Merges consecutive same-type segments for cleaner output.
    private func computeDifferences(
        expectedTokens: [String],
        actualTokens: [String]
    ) -> [DiffSegment] {
        let lcs = computeLCS(expectedTokens, actualTokens)

        var rawSegments: [DiffSegment] = []
        var expIdx = 0
        var actIdx = 0
        var lcsIdx = 0

        while expIdx < expectedTokens.count || actIdx < actualTokens.count {
            if lcsIdx < lcs.count,
               expIdx < expectedTokens.count,
               actIdx < actualTokens.count,
               lcs[lcsIdx] == (expIdx, actIdx) {
                // Correct token
                rawSegments.append(DiffSegment(
                    type: .correct,
                    expectedSegment: expectedTokens[expIdx],
                    actualSegment: actualTokens[actIdx],
                    expectedRange: NSRange(location: expIdx, length: 1),
                    actualRange: NSRange(location: actIdx, length: 1)
                ))
                expIdx += 1; actIdx += 1; lcsIdx += 1
            } else if expIdx < expectedTokens.count,
                      actIdx < actualTokens.count,
                      lcsIdx < lcs.count,
                      lcs[lcsIdx].0 != expIdx,
                      lcs[lcsIdx].1 != actIdx {
                // Both sides have unmatched tokens — substitution
                rawSegments.append(DiffSegment(
                    type: .wrong,
                    expectedSegment: expectedTokens[expIdx],
                    actualSegment: actualTokens[actIdx],
                    expectedRange: NSRange(location: expIdx, length: 1),
                    actualRange: NSRange(location: actIdx, length: 1)
                ))
                expIdx += 1; actIdx += 1
            } else if expIdx < expectedTokens.count,
                      (lcsIdx >= lcs.count || lcs[lcsIdx].0 != expIdx) {
                // Missing token
                rawSegments.append(DiffSegment(
                    type: .missing,
                    expectedSegment: expectedTokens[expIdx],
                    actualSegment: nil,
                    expectedRange: NSRange(location: expIdx, length: 1),
                    actualRange: NSRange(location: actIdx, length: 0)
                ))
                expIdx += 1
            } else if actIdx < actualTokens.count {
                // Extra token
                rawSegments.append(DiffSegment(
                    type: .extra,
                    expectedSegment: nil,
                    actualSegment: actualTokens[actIdx],
                    expectedRange: NSRange(location: expIdx, length: 0),
                    actualRange: NSRange(location: actIdx, length: 1)
                ))
                actIdx += 1
            }
        }

        return mergeConsecutiveSegments(rawSegments).map(classifySubstitution(seg:))
    }

    /// Merges consecutive diff segments of the same type into grouped segments.
    private func mergeConsecutiveSegments(_ segments: [DiffSegment]) -> [DiffSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [DiffSegment] = []
        var current = segments[0]

        for i in 1..<segments.count {
            let next = segments[i]
            if current.type == next.type {
                let mergedExpected = joinSegments(current.expectedSegment, next.expectedSegment)
                let mergedActual = joinSegments(current.actualSegment, next.actualSegment)
                let mergedExpRange = NSRange(
                    location: current.expectedRange.location,
                    length: current.expectedRange.length + next.expectedRange.length
                )
                let mergedActRange = NSRange(
                    location: current.actualRange.location,
                    length: current.actualRange.length + next.actualRange.length
                )
                current = DiffSegment(
                    type: current.type,
                    expectedSegment: mergedExpected,
                    actualSegment: mergedActual,
                    expectedRange: mergedExpRange,
                    actualRange: mergedActRange
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    private func joinSegments(_ a: String?, _ b: String?) -> String? {
        switch (a, b) {
        case let (.some(s1), .some(s2)): return s1 + s2
        case let (.some(s1), nil): return s1
        case let (nil, .some(s2)): return s2
        case (nil, nil): return nil
        }
    }

    // MARK: - LCS Algorithm (Token-Level)
    /// Computes the Longest Common Subsequence at token granularity.
    private func computeLCS(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let m = a.count
        let n = b.count

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [(Int, Int)] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append((i - 1, j - 1))
                i -= 1; j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    // MARK: - Homophone Detection
    /// Converts text to pinyin for homophone comparison.
    /// Uses CFStringTransform (built into iOS, no external deps).
    private func pinyin(of text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        return (mutable as String).lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// Returns true when expected and actual are different characters
    /// but share the same pinyin (homophone / 同音字).
    private func isHomophone(expected: String, actual: String) -> Bool {
        guard expected != actual else { return false }
        let ep = pinyin(of: expected)
        let ap = pinyin(of: actual)
        return !ep.isEmpty && ep == ap
    }

    /// Checks a `.wrong` segment and downgrades it to `.homophone` if applicable.
    private func classifySubstitution(seg: DiffSegment) -> DiffSegment {
        guard seg.type == .wrong,
              let exp = seg.expectedSegment,
              let act = seg.actualSegment,
              isHomophone(expected: exp, actual: act) else {
            return seg
        }
        return DiffSegment(
            type: .homophone,
            expectedSegment: exp,
            actualSegment: act,
            expectedRange: seg.expectedRange,
            actualRange: seg.actualRange
        )
    }

    // MARK: - Score Calculation
    /// Weighted accuracy score:
    ///   correct = 1.0, homophone = 0.5, missing/extra/wrong = 0.0
    private func calculateScore(
        differences: [DiffSegment],
        expectedCount: Int,
        actualCount: Int
    ) -> Double {
        var weightedCorrect = 0.0
        for seg in differences {
            switch seg.type {
            case .correct:
                weightedCorrect += Double(seg.expectedRange.length)
            case .homophone:
                weightedCorrect += Double(seg.expectedRange.length) * 0.8
            case .missing, .extra, .wrong:
                break
            }
        }
        let denominator = max(expectedCount, actualCount, 1)
        let rawScore = weightedCorrect / Double(denominator) * 100.0
        return min(max(rawScore, 0.0), 100.0)
    }
}
