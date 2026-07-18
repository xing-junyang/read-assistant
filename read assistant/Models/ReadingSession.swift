import Foundation

// MARK: - Reading Session Model
/// Represents a single reading session for a specific expected text within a task.
/// Uses NSCoding for iOS 10 persistence compatibility.
class ReadingSession: NSObject, NSCoding {

    // MARK: - Properties
    let id: String
    /// Index of the expected text in the parent task's `expectedTexts` array.
    var expectedTextIndex: Int
    /// The full recognized speech text.
    var recognizedText: String
    /// The diff/scoring result after completion.
    var result: DiffResult?
    /// File path to the recorded audio file (nil if no audio was recorded).
    var audioFilePath: String?
    /// Session start time.
    let startTime: Date
    /// Session end time (nil if not yet finished).
    var endTime: Date?
    /// Duration in seconds.
    var duration: TimeInterval {
        guard let end = endTime else { return Date().timeIntervalSince(startTime) }
        return end.timeIntervalSince(startTime)
    }

    // MARK: - Initialization
    init(id: String = UUID().uuidString,
         expectedTextIndex: Int,
         recognizedText: String = "",
         result: DiffResult? = nil,
         audioFilePath: String? = nil,
         startTime: Date = Date(),
         endTime: Date? = nil) {
        self.id = id
        self.expectedTextIndex = expectedTextIndex
        self.recognizedText = recognizedText
        self.result = result
        self.audioFilePath = audioFilePath
        self.startTime = startTime
        self.endTime = endTime
        super.init()
    }

    // MARK: - NSCoding
    private enum CodingKeys {
        static let id = "id"
        static let expectedTextIndex = "expectedTextIndex"
        static let recognizedText = "recognizedText"
        static let result = "result"
        static let audioFilePath = "audioFilePath"
        static let startTime = "startTime"
        static let endTime = "endTime"
    }

    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: CodingKeys.id)
        coder.encode(expectedTextIndex, forKey: CodingKeys.expectedTextIndex)
        coder.encode(recognizedText, forKey: CodingKeys.recognizedText)
        coder.encode(result, forKey: CodingKeys.result)
        coder.encode(audioFilePath, forKey: CodingKeys.audioFilePath)
        coder.encode(startTime, forKey: CodingKeys.startTime)
        coder.encode(endTime, forKey: CodingKeys.endTime)
    }

    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(forKey: CodingKeys.id) as? String else {
            return nil
        }
        self.id = id
        self.expectedTextIndex = coder.decodeInteger(forKey: CodingKeys.expectedTextIndex)
        self.recognizedText = coder.decodeObject(forKey: CodingKeys.recognizedText) as? String ?? ""
        self.result = coder.decodeObject(forKey: CodingKeys.result) as? DiffResult
        self.audioFilePath = coder.decodeObject(forKey: CodingKeys.audioFilePath) as? String
        self.startTime = coder.decodeObject(forKey: CodingKeys.startTime) as? Date ?? Date()
        self.endTime = coder.decodeObject(forKey: CodingKeys.endTime) as? Date
        super.init()
    }
}
