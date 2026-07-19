import Foundation

// MARK: - Reading Task Model
/// Represents a single reading task created by the user.
/// Uses NSCoding for iOS 10 persistence compatibility.
class ReadingTask: NSObject, NSCoding {

    // MARK: - Properties
    let id: String
    var title: String
    var detailDescription: String
    /// List of expected texts the user needs to read.
    var expectedTexts: [String]
    /// The date this task was created.
    let createdAt: Date
    /// The last modification date.
    var modifiedAt: Date
    /// Order index for manual sorting.
    var sortOrder: Int
    /// Whether this task has been completed.
    var isCompleted: Bool
    /// Whether this is a built-in task that cannot be deleted by the user.
    var isBuiltIn: Bool
    /// Associated reading sessions.
    var sessions: [ReadingSession]

    // MARK: - Initialization
    init(id: String = UUID().uuidString,
         title: String,
         detailDescription: String = "",
         expectedTexts: [String] = [],
         createdAt: Date = Date(),
         modifiedAt: Date = Date(),
         sortOrder: Int = 0,
         isCompleted: Bool = false,
         isBuiltIn: Bool = false,
         sessions: [ReadingSession] = []) {
        self.id = id
        self.title = title
        self.detailDescription = detailDescription
        self.expectedTexts = expectedTexts
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.sortOrder = sortOrder
        self.isCompleted = isCompleted
        self.isBuiltIn = isBuiltIn
        self.sessions = sessions
        super.init()
    }

    /// Convenience: returns a copy with a new ID (for duplication).
    func duplicate() -> ReadingTask {
        return ReadingTask(
            id: UUID().uuidString,
            title: "\(title) (副本)",
            detailDescription: detailDescription,
            expectedTexts: expectedTexts,
            createdAt: Date(),
            modifiedAt: Date(),
            sortOrder: sortOrder,
            isCompleted: false,
            sessions: []
        )
    }

    /// Progress: fraction of expected texts that have been read.
    var progress: Double {
        guard !expectedTexts.isEmpty else { return 0.0 }
        let readCount = expectedTexts.filter { !$0.isEmpty && sessions.contains(where: { $0.expectedTextIndex < expectedTexts.count }) }.count
        return Double(readCount) / Double(expectedTexts.count)
    }

    // MARK: - NSCoding
    private enum CodingKeys {
        static let id = "id"
        static let title = "title"
        static let detailDescription = "detailDescription"
        static let expectedTexts = "expectedTexts"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
        static let sortOrder = "sortOrder"
        static let isCompleted = "isCompleted"
        static let isBuiltIn = "isBuiltIn"
        static let sessions = "sessions"
    }

    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: CodingKeys.id)
        coder.encode(title, forKey: CodingKeys.title)
        coder.encode(detailDescription, forKey: CodingKeys.detailDescription)
        coder.encode(expectedTexts, forKey: CodingKeys.expectedTexts)
        coder.encode(createdAt, forKey: CodingKeys.createdAt)
        coder.encode(modifiedAt, forKey: CodingKeys.modifiedAt)
        coder.encode(sortOrder, forKey: CodingKeys.sortOrder)
        coder.encode(isCompleted, forKey: CodingKeys.isCompleted)
        coder.encode(isBuiltIn, forKey: CodingKeys.isBuiltIn)
        coder.encode(sessions, forKey: CodingKeys.sessions)
    }

    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(forKey: CodingKeys.id) as? String,
              let title = coder.decodeObject(forKey: CodingKeys.title) as? String else {
            return nil
        }
        self.id = id
        self.title = title
        self.detailDescription = coder.decodeObject(forKey: CodingKeys.detailDescription) as? String ?? ""
        self.expectedTexts = coder.decodeObject(forKey: CodingKeys.expectedTexts) as? [String] ?? []
        self.createdAt = coder.decodeObject(forKey: CodingKeys.createdAt) as? Date ?? Date()
        self.modifiedAt = coder.decodeObject(forKey: CodingKeys.modifiedAt) as? Date ?? Date()
        self.sortOrder = coder.decodeInteger(forKey: CodingKeys.sortOrder)
        self.isCompleted = coder.decodeBool(forKey: CodingKeys.isCompleted)
        self.isBuiltIn = coder.decodeBool(forKey: CodingKeys.isBuiltIn)
        self.sessions = coder.decodeObject(forKey: CodingKeys.sessions) as? [ReadingSession] ?? []
        super.init()
    }
}
