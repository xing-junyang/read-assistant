import Foundation

// MARK: - Diff Scoring Service
/// Implements text comparison using a word-level diff algorithm
/// to compute accuracy scores between expected and actual text.
final class DiffScoringService: ScoringServiceProtocol {

    // MARK: - ScoringServiceProtocol

    func compare(expected: String, actual: String) -> DiffResult {
        let normalizedExpected = normalizeText(expected)
        let normalizedActual = normalizeText(actual)

        // Split into words for comparison
        let expectedWords = normalizedExpected.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let actualWords = normalizedActual.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        let differences = computeDifferences(expectedWords: expectedWords, actualWords: actualWords)
        let score = calculateScore(differences: differences, expectedWordCount: expectedWords.count)

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
    /// Normalizes text for comparison: trims whitespace, collapses newlines,
    /// removes punctuation edge cases.
    private func normalizeText(_ text: String) -> String {
        var result = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Normalize common Chinese punctuation
        result = result.replacingOccurrences(of: "，", with: ",")
        result = result.replacingOccurrences(of: "。", with: ".")
        result = result.replacingOccurrences(of: "；", with: ";")
        result = result.replacingOccurrences(of: "：", with: ":")
        result = result.replacingOccurrences(of: "\"", with: "\"")
        result = result.replacingOccurrences(of: "\"", with: "\"")
        result = result.replacingOccurrences(of: "'", with: "'")
        result = result.replacingOccurrences(of: "'", with: "'")

        return result
    }

    // MARK: - Diff Algorithm
    /// Computes word-level differences using a simplified LCS-based approach.
    private func computeDifferences(expectedWords: [String], actualWords: [String]) -> [DiffSegment] {
        let lcs = computeLCS(expectedWords, actualWords)
        var differences: [DiffSegment] = []
        var expIdx = 0
        var actIdx = 0
        var lcsIdx = 0

        while expIdx < expectedWords.count || actIdx < actualWords.count {
            if lcsIdx < lcs.count,
               expIdx < expectedWords.count,
               actIdx < actualWords.count,
               lcs[lcsIdx] == (expIdx, actIdx) {
                // Correct word
                let range = wordRange(expectedWords[expIdx], in: expectedWords, from: expIdx)
                let seg = DiffSegment(
                    type: .correct,
                    expectedSegment: expectedWords[expIdx],
                    actualSegment: actualWords[actIdx],
                    expectedRange: NSRange(location: expIdx, length: 1),
                    actualRange: NSRange(location: actIdx, length: 1)
                )
                differences.append(seg)
                expIdx += 1
                actIdx += 1
                lcsIdx += 1
            } else if expIdx < expectedWords.count,
                      (lcsIdx >= lcs.count || lcs[lcsIdx].0 != expIdx) {
                // Missing word (expected but not in actual)
                let seg = DiffSegment(
                    type: .missing,
                    expectedSegment: expectedWords[expIdx],
                    actualSegment: nil,
                    expectedRange: NSRange(location: expIdx, length: 1),
                    actualRange: NSRange(location: actIdx, length: 0)
                )
                differences.append(seg)
                expIdx += 1
            } else if actIdx < actualWords.count {
                // Extra word (in actual but not expected)
                let seg = DiffSegment(
                    type: .extra,
                    expectedSegment: nil,
                    actualSegment: actualWords[actIdx],
                    expectedRange: NSRange(location: expIdx, length: 0),
                    actualRange: NSRange(location: actIdx, length: 1)
                )
                differences.append(seg)
                actIdx += 1
            }
        }

        return differences
    }

    /// Computes the Longest Common Subsequence of word indices.
    private func computeLCS(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let m = a.count
        let n = b.count

        // Build DP table
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

        // Backtrack to find LCS
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

    /// Returns the word range in a joined context.
    private func wordRange(_ word: String, in words: [String], from index: Int) -> NSRange {
        var loc = 0
        for i in 0..<index {
            loc += words[i].count + 1 // +1 for space
        }
        return NSRange(location: loc, length: word.count)
    }

    // MARK: - Score Calculation
    /// Calculates accuracy score as a percentage.
    /// Score = (correct_words / max(expected_words, actual_words)) * 100
    private func calculateScore(differences: [DiffSegment], expectedWordCount: Int) -> Double {
        let correctCount = differences.filter { $0.type == .correct }.count
        let denominator = max(expectedWordCount, 1)
        let rawScore = Double(correctCount) / Double(denominator) * 100.0
        return min(max(rawScore, 0.0), 100.0)
    }
}
