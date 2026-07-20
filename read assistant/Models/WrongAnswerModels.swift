import Foundation

// MARK: - Wrong Answer Item
/// Represents a single wrong/missed word from a reading session.
/// Uses NSCoding for iOS 10 persistence compatibility.
class WrongAnswerItem: NSObject, NSCoding {

    /// The expected (correct) Chinese text (≤5 characters).
    let correctText: String
    /// The actual (wrong) text that was read, if available.
    let wrongText: String?
    /// Pinyin of the correct text.
    let correctPinyin: String
    /// Pinyin of the wrong text (if available).
    let wrongPinyin: String?
    /// The type of error.
    let errorType: ErrorType
    /// ID of the session where this error occurred.
    let sessionID: String
    /// When this error was recorded.
    let timestamp: Date
    /// Unique identifier.
    let id: String

    enum ErrorType: Int {
        case wrong = 0       // Substitution (wrong character)
        case missing = 1     // Expected text was missing
        case homophone = 2   // Same pinyin, wrong character
    }

    init(id: String = UUID().uuidString,
         correctText: String,
         wrongText: String? = nil,
         correctPinyin: String,
         wrongPinyin: String? = nil,
         errorType: ErrorType,
         sessionID: String,
         timestamp: Date = Date()) {
        self.id = id
        self.correctText = correctText
        self.wrongText = wrongText
        self.correctPinyin = correctPinyin
        self.wrongPinyin = wrongPinyin
        self.errorType = errorType
        self.sessionID = sessionID
        self.timestamp = timestamp
        super.init()
    }

    // MARK: - NSCoding
    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(correctText, forKey: "correctText")
        coder.encode(wrongText, forKey: "wrongText")
        coder.encode(correctPinyin, forKey: "correctPinyin")
        coder.encode(wrongPinyin, forKey: "wrongPinyin")
        coder.encode(errorType.rawValue, forKey: "errorType")
        coder.encode(sessionID, forKey: "sessionID")
        coder.encode(timestamp, forKey: "timestamp")
    }

    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(forKey: "id") as? String,
              let correctText = coder.decodeObject(forKey: "correctText") as? String,
              let correctPinyin = coder.decodeObject(forKey: "correctPinyin") as? String,
              let sessionID = coder.decodeObject(forKey: "sessionID") as? String,
              let timestamp = coder.decodeObject(forKey: "timestamp") as? Date else {
            return nil
        }
        self.id = id
        self.correctText = correctText
        self.wrongText = coder.decodeObject(forKey: "wrongText") as? String
        self.correctPinyin = correctPinyin
        self.wrongPinyin = coder.decodeObject(forKey: "wrongPinyin") as? String
        self.errorType = ErrorType(rawValue: coder.decodeInteger(forKey: "errorType")) ?? .wrong
        self.sessionID = sessionID
        self.timestamp = timestamp
        super.init()
    }
}

// MARK: - Quiz Question
/// Represents a single quiz question.
struct QuizQuestion {
    /// The correct answer text (Chinese or Pinyin).
    let correctAnswer: String
    /// All 4 option texts.
    let options: [String]
    /// Index of the correct answer in options.
    let correctIndex: Int
    /// The original wrong answer item this question is based on.
    let sourceItem: WrongAnswerItem
    /// Question type.
    let questionType: QuestionType

    enum QuestionType: Int {
        case characterToPinyin = 0  // 看字选拼音
        case pinyinToCharacter = 1  // 看拼音选字
    }
}

// MARK: - Quiz Question Data
/// Serializable question data stored within a quiz session.
/// Top-level class (not nested) for stable NSCoding archive names.
class QuizQuestionData: NSObject, NSCoding {
    let correctAnswer: String
    let options: [String]
    let correctIndex: Int
    let questionType: Int  // 0 = charToPinyin, 1 = pinyinToChar
    let sourceItemID: String  // Links back to WrongAnswerItem

    init(correctAnswer: String, options: [String], correctIndex: Int, questionType: Int, sourceItemID: String) {
        self.correctAnswer = correctAnswer
        self.options = options
        self.correctIndex = correctIndex
        self.questionType = questionType
        self.sourceItemID = sourceItemID
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(correctAnswer, forKey: "correctAnswer")
        coder.encode(options, forKey: "options")
        coder.encode(correctIndex, forKey: "correctIndex")
        coder.encode(questionType, forKey: "questionType")
        coder.encode(sourceItemID, forKey: "sourceItemID")
    }

    required init?(coder: NSCoder) {
        guard let correctAnswer = coder.decodeObject(forKey: "correctAnswer") as? String,
              let options = coder.decodeObject(forKey: "options") as? [String],
              let sourceItemID = coder.decodeObject(forKey: "sourceItemID") as? String else {
            return nil
        }
        self.correctAnswer = correctAnswer
        self.options = options
        self.correctIndex = coder.decodeInteger(forKey: "correctIndex")
        self.questionType = coder.decodeInteger(forKey: "questionType")
        self.sourceItemID = sourceItemID
        super.init()
    }
}

// MARK: - Quiz Session
/// Tracks a quiz session (one level = 10 questions).
class QuizSession: NSObject, NSCoding {
    let id: String
    let levelNumber: Int
    let questions: [QuizQuestionData]
    var userAnswers: [Int]  // Indices of user's selections (-1 if not answered)
    let startTime: Date
    var endTime: Date?
    /// Did the user complete this level?
    var isCompleted: Bool
    /// Coins earned from this session (0 if none, negative if spent).
    var coinsEarned: Int

    /// Result tier based on score percentage.
    enum ResultTier: Int {
        case completeVictory = 0  // >= 90% — earn 3 coins, advance
        case success = 1          // >= 60% — no coins, advance
        case failure = 2          // < 60% — no advance
    }

    /// Computed result tier.
    var resultTier: ResultTier {
        let pct = totalQuestions > 0 ? Double(score) / Double(totalQuestions) * 100 : 0
        if pct >= 90 { return .completeVictory }
        if pct >= 60 { return .success }
        return .failure
    }

    var score: Int {
        var correct = 0
        for (i, answer) in userAnswers.enumerated() {
            if i < questions.count && answer == questions[i].correctIndex {
                correct += 1
            }
        }
        return correct
    }

    var totalQuestions: Int {
        return questions.count
    }

    init(id: String = UUID().uuidString,
         levelNumber: Int,
         questions: [QuizQuestionData],
         startTime: Date = Date()) {
        self.id = id
        self.levelNumber = levelNumber
        self.questions = questions
        self.userAnswers = Array(repeating: -1, count: questions.count)
        self.startTime = startTime
        self.isCompleted = false
        self.coinsEarned = 0
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(id, forKey: "id")
        coder.encode(levelNumber, forKey: "levelNumber")
        coder.encode(questions, forKey: "questions")
        coder.encode(userAnswers, forKey: "userAnswers")
        coder.encode(startTime, forKey: "startTime")
        coder.encode(endTime, forKey: "endTime")
        coder.encode(isCompleted, forKey: "isCompleted")
        coder.encode(coinsEarned, forKey: "coinsEarned")
    }

    required init?(coder: NSCoder) {
        guard let id = coder.decodeObject(forKey: "id") as? String,
              let questions = coder.decodeObject(forKey: "questions") as? [QuizQuestionData],
              let startTime = coder.decodeObject(forKey: "startTime") as? Date else {
            return nil
        }
        self.id = id
        self.levelNumber = coder.decodeInteger(forKey: "levelNumber")
        self.questions = questions
        self.userAnswers = coder.decodeObject(forKey: "userAnswers") as? [Int] ?? Array(repeating: -1, count: questions.count)
        self.startTime = startTime
        self.endTime = coder.decodeObject(forKey: "endTime") as? Date
        self.isCompleted = coder.decodeBool(forKey: "isCompleted")
        self.coinsEarned = coder.decodeInteger(forKey: "coinsEarned")
        super.init()
    }
}

// MARK: - Quiz Progress
/// Tracks overall quiz progress: total levels completed.
class QuizProgress: NSObject, NSCoding {
    /// Total number of levels completed.
    var totalLevelsCompleted: Int
    /// History of all quiz sessions.
    var sessionHistory: [QuizSession]
    /// Number of consecutive complete victories (>= 90% score).
    /// Resets to 0 on any non-complete-victory result.
    var consecutiveCompleteVictories: Int

    init(totalLevelsCompleted: Int = 0, sessionHistory: [QuizSession] = [], consecutiveCompleteVictories: Int = 0) {
        self.totalLevelsCompleted = totalLevelsCompleted
        self.sessionHistory = sessionHistory
        self.consecutiveCompleteVictories = consecutiveCompleteVictories
        super.init()
    }

    func encode(with coder: NSCoder) {
        coder.encode(totalLevelsCompleted, forKey: "totalLevelsCompleted")
        coder.encode(sessionHistory, forKey: "sessionHistory")
        coder.encode(consecutiveCompleteVictories, forKey: "consecutiveCompleteVictories")
    }

    required init?(coder: NSCoder) {
        self.totalLevelsCompleted = coder.decodeInteger(forKey: "totalLevelsCompleted")
        self.sessionHistory = coder.decodeObject(forKey: "sessionHistory") as? [QuizSession] ?? []
        self.consecutiveCompleteVictories = coder.decodeInteger(forKey: "consecutiveCompleteVictories")
        super.init()
    }
}
