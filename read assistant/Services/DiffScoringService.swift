import Foundation

// MARK: - Diff Scoring Service
/// Implements text comparison using a character-level LCS diff algorithm
/// optimized for Chinese text (where whitespace-based word splitting is unreliable).
final class DiffScoringService: ScoringServiceProtocol {

    // MARK: - ScoringServiceProtocol

    func compare(expected: String, actual: String) -> DiffResult {
        let normalizedExpected = normalizeText(expected)
        let normalizedActual = normalizeText(actual)

        // Character-level diff for Chinese-friendly comparison
        let expectedChars = Array(normalizedExpected)
        let actualChars = Array(normalizedActual)

        let differences = computeDifferences(
            expectedChars: expectedChars,
            actualChars: actualChars
        )
        let score = calculateScore(
            differences: differences,
            expectedCount: expectedChars.count,
            actualCount: actualChars.count
        )

        return DiffResult(
            differences: differences,
            score: score,
            expectedText: expected,
            actualText: actual
        )
    }

    func aggregateScore(from results: [DiffResult]) -> Double {
        guard !results.isEmpty else { return 100.0 }
        let total = results.reduce(0.0) { $0 + $1.score }
        return total / Double(results.count)
    }

    // MARK: - Text Normalization
    /// Normalizes text for comparison: trims whitespace, collapses spaces,
    /// and normalizes Chinese punctuation to ASCII equivalents.
    private func normalizeText(_ text: String) -> String {
        var result = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)

        // Normalize common Chinese punctuation to ASCII for fairer comparison
        result = result.replacingOccurrences(of: "，", with: ",")
        result = result.replacingOccurrences(of: "。", with: ".")
        result = result.replacingOccurrences(of: "；", with: ";")
        result = result.replacingOccurrences(of: "：", with: ":")
        result = result.replacingOccurrences(of: "？", with: "?")
        result = result.replacingOccurrences(of: "！", with: "!")
        result = result.replacingOccurrences(of: "\u{201c}", with: "\"") // "
        result = result.replacingOccurrences(of: "\u{201d}", with: "\"") // "
        result = result.replacingOccurrences(of: "\u{2018}", with: "'")  // '
        result = result.replacingOccurrences(of: "\u{2019}", with: "'")  // '
        result = result.replacingOccurrences(of: "（", with: "(")
        result = result.replacingOccurrences(of: "）", with: ")")

        return result
    }

    // MARK: - Character-Level Diff Algorithm
    /// Computes character-level differences using LCS (Longest Common Subsequence).
    /// Merges consecutive same-type segments for cleaner output.
    private func computeDifferences(
        expectedChars: [Character],
        actualChars: [Character]
    ) -> [DiffSegment] {
        let lcs = computeLCS(expectedChars, actualChars)

        // Step 1: Build raw character-level diffs
        var rawSegments: [DiffSegment] = []
        var expIdx = 0
        var actIdx = 0
        var lcsIdx = 0

        while expIdx < expectedChars.count || actIdx < actualChars.count {
            if lcsIdx < lcs.count,
               expIdx < expectedChars.count,
               actIdx < actualChars.count,
               lcs[lcsIdx] == (expIdx, actIdx) {
                // Correct character
                let seg = DiffSegment(
                    type: .correct,
                    expectedSegment: String(expectedChars[expIdx]),
                    actualSegment: String(actualChars[actIdx]),
                    expectedRange: NSRange(location: expIdx, length: 1),
                    actualRange: NSRange(location: actIdx, length: 1)
                )
                rawSegments.append(seg)
                expIdx += 1
                actIdx += 1
                lcsIdx += 1
            } else if expIdx < expectedChars.count,
                      actIdx < actualChars.count,
                      lcsIdx < lcs.count,
                      lcs[lcsIdx].0 != expIdx,
                      lcs[lcsIdx].1 != actIdx {
                // Both sides have characters that don't match — treat as substitution (wrong)
                let seg = DiffSegment(
                    type: .wrong,
                    expectedSegment: String(expectedChars[expIdx]),
                    actualSegment: String(actualChars[actIdx]),
                    expectedRange: NSRange(location: expIdx, length: 1),
                    actualRange: NSRange(location: actIdx, length: 1)
                )
                rawSegments.append(seg)
                expIdx += 1
                actIdx += 1
            } else if expIdx < expectedChars.count,
                      (lcsIdx >= lcs.count || lcs[lcsIdx].0 != expIdx) {
                // Missing character (in expected but not in actual)
                let seg = DiffSegment(
                    type: .missing,
                    expectedSegment: String(expectedChars[expIdx]),
                    actualSegment: nil,
                    expectedRange: NSRange(location: expIdx, length: 1),
                    actualRange: NSRange(location: actIdx, length: 0)
                )
                rawSegments.append(seg)
                expIdx += 1
            } else if actIdx < actualChars.count {
                // Extra character (in actual but not in expected)
                let seg = DiffSegment(
                    type: .extra,
                    expectedSegment: nil,
                    actualSegment: String(actualChars[actIdx]),
                    expectedRange: NSRange(location: expIdx, length: 0),
                    actualRange: NSRange(location: actIdx, length: 1)
                )
                rawSegments.append(seg)
                actIdx += 1
            }
        }

        // Step 2: Merge consecutive segments of the same type
        return mergeConsecutiveSegments(rawSegments)
    }

    /// Merges consecutive diff segments of the same type into larger segments
    /// so the result view shows grouped diffs instead of individual characters.
    private func mergeConsecutiveSegments(_ segments: [DiffSegment]) -> [DiffSegment] {
        guard !segments.isEmpty else { return [] }

        var merged: [DiffSegment] = []
        var current = segments[0]

        for i in 1..<segments.count {
            let next = segments[i]
            if current.type == next.type {
                // Merge into current
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

    // MARK: - LCS Algorithm (Character-Level)
    /// Computes the Longest Common Subsequence at character granularity.
    /// Returns an array of (expectedIndex, actualIndex) matched pairs.
    private func computeLCS(_ a: [Character], _ b: [Character]) -> [(Int, Int)] {
        let m = a.count
        let n = b.count

        // DP table
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

        // Backtrack to build LCS
        var result: [(Int, Int)] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append((i - 1, j - 1))
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result.reversed()
    }

    // MARK: - Score Calculation
    /// Calculates accuracy score at character level.
    /// Score = (correct_characters / max(expected_count, actual_count)) * 100
    private func calculateScore(
        differences: [DiffSegment],
        expectedCount: Int,
        actualCount: Int
    ) -> Double {
        let correctCount = differences
            .filter { $0.type == .correct }
            .reduce(0) { $0 + $1.expectedRange.length }
        let denominator = max(expectedCount, actualCount, 1)
        let rawScore = Double(correctCount) / Double(denominator) * 100.0
        return min(max(rawScore, 0.0), 100.0)
    }
}
