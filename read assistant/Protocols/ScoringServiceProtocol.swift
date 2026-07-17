import Foundation

// MARK: - Scoring Service Protocol (Pluggable)
/// Protocol defining the text comparison and scoring service.
/// Implementations can use diff-based, Levenshtein, or semantic comparison.
protocol ScoringServiceProtocol: AnyObject {

    /// Compares expected text with actual (recognized) text and produces a score with diffs.
    /// - Parameters:
    ///   - expected: The expected/desired text that should have been read.
    ///   - actual: The actual speech-recognized text.
    /// - Returns: A `DiffResult` containing the score and detailed differences.
    func compare(expected: String, actual: String) -> DiffResult

    /// Computes an overall score across multiple text pairs.
    /// - Parameter results: Array of individual `DiffResult` objects.
    /// - Returns: Overall score as a percentage (0.0 - 100.0).
    func aggregateScore(from results: [DiffResult]) -> Double
}

// MARK: - Diff Result Model
/// Represents the result of comparing expected vs. actual text.
class DiffResult: NSObject, NSCoding {
    /// Individual segment differences.
    let differences: [DiffSegment]
    /// Overall accuracy score (0.0 - 100.0).
    let score: Double
    /// The original expected text.
    let expectedText: String
    /// The actual recognized text.
    let actualText: String
    /// Timestamp when this result was created.
    let timestamp: Date

    init(differences: [DiffSegment],
         score: Double,
         expectedText: String,
         actualText: String,
         timestamp: Date = Date()) {
        self.differences = differences
        self.score = score
        self.expectedText = expectedText
        self.actualText = actualText
        self.timestamp = timestamp
        super.init()
    }

    // MARK: - NSCoding
    func encode(with coder: NSCoder) {
        coder.encode(differences, forKey: "differences")
        coder.encode(score, forKey: "score")
        coder.encode(expectedText, forKey: "expectedText")
        coder.encode(actualText, forKey: "actualText")
        coder.encode(timestamp, forKey: "timestamp")
    }

    required init?(coder: NSCoder) {
        guard let differences = coder.decodeObject(forKey: "differences") as? [DiffSegment],
              let expectedText = coder.decodeObject(forKey: "expectedText") as? String,
              let actualText = coder.decodeObject(forKey: "actualText") as? String,
              let timestamp = coder.decodeObject(forKey: "timestamp") as? Date else {
            return nil
        }
        self.differences = differences
        self.score = coder.decodeDouble(forKey: "score")
        self.expectedText = expectedText
        self.actualText = actualText
        self.timestamp = timestamp
        super.init()
    }
}

// MARK: - Diff Segment
/// A single difference segment between expected and actual text.
class DiffSegment: NSObject, NSCoding {
    enum DiffType: Int {
        case correct = 0   // Text matches expected.
        case missing = 1   // Expected text is missing from actual.
        case extra = 2     // Extra text in actual not in expected.
        case wrong = 3     // Text differs from expected.
    }

    let type: DiffType
    let expectedSegment: String?
    let actualSegment: String?
    /// Character range in the expected text (for highlighting).
    let expectedRange: NSRange
    /// Character range in the actual text (for highlighting).
    let actualRange: NSRange

    init(type: DiffType,
         expectedSegment: String?,
         actualSegment: String?,
         expectedRange: NSRange,
         actualRange: NSRange) {
        self.type = type
        self.expectedSegment = expectedSegment
        self.actualSegment = actualSegment
        self.expectedRange = expectedRange
        self.actualRange = actualRange
        super.init()
    }

    // MARK: - NSCoding
    func encode(with coder: NSCoder) {
        coder.encode(type.rawValue, forKey: "type")
        coder.encode(expectedSegment, forKey: "expectedSegment")
        coder.encode(actualSegment, forKey: "actualSegment")
        coder.encode(Int64(expectedRange.location), forKey: "expectedLoc")
        coder.encode(Int64(expectedRange.length), forKey: "expectedLen")
        coder.encode(Int64(actualRange.location), forKey: "actualLoc")
        coder.encode(Int64(actualRange.length), forKey: "actualLen")
    }

    required init?(coder: NSCoder) {
        self.type = DiffType(rawValue: coder.decodeInteger(forKey: "type")) ?? .wrong
        self.expectedSegment = coder.decodeObject(forKey: "expectedSegment") as? String
        self.actualSegment = coder.decodeObject(forKey: "actualSegment") as? String
        let expLoc = Int(coder.decodeInt64(forKey: "expectedLoc"))
        let expLen = Int(coder.decodeInt64(forKey: "expectedLen"))
        self.expectedRange = NSRange(location: expLoc, length: expLen)
        let actLoc = Int(coder.decodeInt64(forKey: "actualLoc"))
        let actLen = Int(coder.decodeInt64(forKey: "actualLen"))
        self.actualRange = NSRange(location: actLoc, length: actLen)
        super.init()
    }
}
