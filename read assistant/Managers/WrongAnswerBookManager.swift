import Foundation

// MARK: - Wrong Answer Book Manager
/// Manages wrong answer collection from reading history, caching,
/// incremental updates, and quiz question generation.
final class WrongAnswerBookManager {

    // MARK: - Singleton
    static let shared = WrongAnswerBookManager()

    // MARK: - Properties
    private(set) var wrongAnswers: [WrongAnswerItem] = []
    private var lastSyncTimestamp: Date?
    private let cacheURL: URL
    private let storageQueue = DispatchQueue(label: "com.readassistant.wronganswer.storage", qos: .utility)

    /// Set of session IDs already processed (for incremental updates).
    private var processedSessionIDs: Set<String> = []

    // MARK: - Quiz Progress
    private(set) var quizProgress: QuizProgress = QuizProgress()
    private let quizProgressURL: URL

    // MARK: - Pinyin Character Database
    /// Maps pinyin (without tone) to an array of common characters with that pinyin.
    /// Used for distractor generation.
    private var pinyinToChars: [String: [String]] = [:]

    // MARK: - Initialization
    private init() {
        let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        cacheURL = URL(fileURLWithPath: docsDir).appendingPathComponent("wrong_answers.archive")
        quizProgressURL = URL(fileURLWithPath: docsDir).appendingPathComponent("quiz_progress.archive")
        loadCache()
        loadQuizProgress()
        buildPinyinDatabase()
    }

    // MARK: - Sync (Incremental Update)

    /// Synchronizes wrong answers from reading history.
    /// Only processes sessions newer than the last sync timestamp.
    /// - Parameter force: If true, re-processes all sessions regardless of timestamp.
    func syncWrongAnswers(force: Bool = false) {
        storageQueue.async { [weak self] in
            guard let self = self else { return }
            let tasks = TaskManager.shared.tasks
            var newItems: [WrongAnswerItem] = []
            var newSessionIDs: Set<String> = []

            let cutoffDate = force ? Date.distantPast : (self.lastSyncTimestamp ?? Date.distantPast)

            for task in tasks {
                for session in task.sessions {
                    // Skip already-processed sessions unless forcing
                    if !force && self.processedSessionIDs.contains(session.id) {
                        continue
                    }
                    // Only process sessions newer than last sync
                    let sessionDate = session.endTime ?? session.startTime
                    if sessionDate <= cutoffDate && !force {
                        continue
                    }
                    newSessionIDs.insert(session.id)

                    // Extract wrong answers from the session result
                    guard let result = session.result else { continue }
                    let items = self.extractWrongAnswers(from: result, sessionID: session.id, task: task)
                    newItems.append(contentsOf: items)
                }
            }

            if !newItems.isEmpty || force {
                // Merge: keep existing items from unprocessed sessions, add new items
                if force {
                    self.wrongAnswers = newItems
                } else {
                    // Deduplicate by (correctText, correctPinyin) pair
                    var existingMap: [String: WrongAnswerItem] = [:]
                    for item in self.wrongAnswers {
                        let key = "\(item.correctText)|\(item.correctPinyin)"
                        if existingMap[key] == nil {
                            existingMap[key] = item
                        }
                    }
                    for item in newItems {
                        let key = "\(item.correctText)|\(item.correctPinyin)"
                        if existingMap[key] == nil {
                            existingMap[key] = item
                        } else {
                            // Update timestamp to latest
                            existingMap[key] = item
                        }
                    }
                    self.wrongAnswers = Array(existingMap.values).sorted { $0.timestamp > $1.timestamp }
                }

                self.processedSessionIDs.formUnion(newSessionIDs)
                self.lastSyncTimestamp = Date()
                self.saveCache()
            }
        }
    }

    /// Waits for any pending sync to complete (for UI readiness).
    func waitForSync(completion: @escaping () -> Void) {
        storageQueue.async { [weak self] in
            guard self != nil else {
                DispatchQueue.main.async { completion() }
                return
            }
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - Wrong Answer Extraction

    /// Extracts wrong answer items from a DiffResult.
    /// Only captures items with ≤5 characters for the correct text.
    private func extractWrongAnswers(from result: DiffResult, sessionID: String, task: ReadingTask) -> [WrongAnswerItem] {
        var items: [WrongAnswerItem] = []

        for segment in result.differences {
            switch segment.type {
            case .wrong, .homophone:
                guard let expected = segment.expectedSegment,
                      let actual = segment.actualSegment,
                      expected.count <= 5,
                      !expected.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                // Skip punctuation-only segments
                let expectedClean = expected.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                guard !expectedClean.isEmpty else { continue }

                let correctPinyin = pinyin(of: expected)
                let wrongPinyin = pinyin(of: actual)

                let errorType: WrongAnswerItem.ErrorType = segment.type == .homophone ? .homophone : .wrong

                // Only add if there's a meaningful difference
                if expected != actual || segment.type == .homophone {
                    items.append(WrongAnswerItem(
                        correctText: expected,
                        wrongText: actual,
                        correctPinyin: correctPinyin,
                        wrongPinyin: wrongPinyin != correctPinyin ? wrongPinyin : nil,
                        errorType: errorType,
                        sessionID: sessionID,
                        timestamp: result.timestamp
                    ))
                }

            case .missing:
                guard let expected = segment.expectedSegment,
                      expected.count <= 5,
                      !expected.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

                let expectedClean = expected.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                guard !expectedClean.isEmpty else { continue }

                let correctPinyin = pinyin(of: expected)
                items.append(WrongAnswerItem(
                    correctText: expected,
                    wrongText: nil,
                    correctPinyin: correctPinyin,
                    wrongPinyin: nil,
                    errorType: .missing,
                    sessionID: sessionID,
                    timestamp: result.timestamp
                ))

            default:
                break
            }
        }

        return items
    }

    // MARK: - Quiz Generation

    /// Extracts meaningful Chinese words from text using tokenization.
    /// Falls back to individual Chinese characters if no multi-character words are found.
    private func extractMeaningfulTokens(from text: String) -> [String] {
        var tokens: [String] = []

        // Use CFStringTokenizer for Chinese word segmentation
        let range = CFRange(location: 0, length: text.utf16.count)
        let locale = NSLocale(localeIdentifier: "zh_CN")
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            text as CFString,
            range,
            kCFStringTokenizerUnitWord,
            locale
        )

        var tokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0)
        while tokenType != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let start = text.utf16.index(text.utf16.startIndex, offsetBy: tokenRange.location)
            let end = text.utf16.index(start, offsetBy: tokenRange.length)
            let token = String(text[start..<end])

            // Only keep meaningful Chinese word tokens (2-4 characters, CJK)
            if token.count >= 2 && token.count <= 4 && isCJKText(token) {
                tokens.append(token)
            }

            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        // If no meaningful multi-char tokens found, fallback to single characters
        if tokens.isEmpty {
            for char in text {
                let s = String(char)
                if isCJKText(s) {
                    tokens.append(s)
                }
            }
        }

        return tokens
    }

    /// Checks whether a string consists entirely of CJK Unified Ideographs.
    private func isCJKText(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            let isCJKUnified = (v >= 0x4E00 && v <= 0x9FFF)
            let isCJKExtA = (v >= 0x3400 && v <= 0x4DBF)
            if !isCJKUnified && !isCJKExtA {
                return false
            }
        }
        return !text.isEmpty
    }

    /// Generates a quiz level by extracting meaningful words from wrong answer items,
    /// then creating questions with strong distractors.
    func generateQuizLevel() -> [QuizQuestion]? {
        guard wrongAnswers.count >= 4 else { return nil }

        // Step 1: Extract meaningful tokens from all wrong answer items
        var allTokens: [(token: String, sourceItem: WrongAnswerItem)] = []
        for item in wrongAnswers {
            let tokens = extractMeaningfulTokens(from: item.correctText)
            for token in tokens {
                allTokens.append((token: token, sourceItem: item))
            }
        }

        // Step 2: Deduplicate tokens (keep unique by token text)
        var seen: Set<String> = []
        var uniqueTokens: [(token: String, sourceItem: WrongAnswerItem)] = []
        for entry in allTokens {
            if !seen.contains(entry.token) {
                seen.insert(entry.token)
                uniqueTokens.append(entry)
            }
        }

        // Need at least 4 unique tokens
        guard uniqueTokens.count >= 4 else { return nil }

        // Step 3: Select up to 10 tokens
        let poolSize = min(uniqueTokens.count, 10)
        let selected = uniqueTokens.shuffled().prefix(poolSize)
        var questions: [QuizQuestion] = []

        for entry in selected {
            let token = entry.token
            let sourceItem = entry.sourceItem

            // Create a synthetic WrongAnswerItem for this token
            let tokenPinyin = pinyin(of: token)
            let quizItem = WrongAnswerItem(
                correctText: token,
                wrongText: nil,
                correctPinyin: normalizePinyin(tokenPinyin),
                wrongPinyin: nil,
                errorType: sourceItem.errorType,
                sessionID: sourceItem.sessionID,
                timestamp: sourceItem.timestamp
            )

            // Randomly choose question type
            let qType: QuizQuestion.QuestionType = Bool.random() ? .characterToPinyin : .pinyinToCharacter

            let correctText = quizItem.correctText
            let tonedPinyin = pinyin(of: correctText)
            let correctPinyin = normalizePinyin(quizItem.correctPinyin)
            let charCount = correctText.count

            if qType == .characterToPinyin {
                // 看字选拼音: show character(s), choose correct pinyin with tones
                var distractors: [String] = []
                if charCount == 1 {
                    distractors = generateTonedPinyinDistractors(for: correctPinyin, correctToned: tonedPinyin)
                } else {
                    distractors = generateMultiSyllablePinyinDistractors(for: correctPinyin, syllableCount: charCount)
                    // Add tones to multi-syllable distractors
                    distractors = distractors.map { addRandomTonesToSyllables($0) }
                }

                // Fill remaining distractors
                while distractors.count < 3 {
                    let rand = generateRandomPinyin(length: charCount)
                    let toned = addRandomTonesToSyllables(rand)
                    distractors.append(toned)
                }
                distractors = Array(distractors.prefix(3))

                // Deduplicate and ensure correct answer is unique
                var options = Array(Set(distractors + [tonedPinyin]))
                // Remove any accidental duplicate of correct answer from distractors
                options.removeAll { $0 == tonedPinyin }
                options = Array(options.prefix(3)) + [tonedPinyin]
                options.shuffle()
                guard let correctIndex = options.firstIndex(of: tonedPinyin), options.count == 4 else { continue }

                questions.append(QuizQuestion(
                    correctAnswer: tonedPinyin,
                    options: options,
                    correctIndex: correctIndex,
                    sourceItem: quizItem,
                    questionType: .characterToPinyin
                ))
            } else {
                // 看拼音选字: show pinyin, choose correct character(s)
                // CRITICAL: distractors must NOT share the same pinyin as the correct answer
                var distractors: [String] = []
                if charCount == 1 {
                    distractors = generateCharacterDistractors(for: correctText, correctPinyin: correctPinyin)
                } else {
                    distractors = generateMultiCharWordDistractors(for: correctText, correctPinyin: correctPinyin, charCount: charCount)
                }

                // Filter out any distractor that has the same pinyin as the correct answer
                distractors = distractors.filter { d in
                    normalizePinyin(pinyin(of: d)) != correctPinyin
                }

                while distractors.count < 3 {
                    if let randomWord = getRandomWord(length: charCount) {
                        if normalizePinyin(pinyin(of: randomWord)) != correctPinyin {
                            distractors.append(randomWord)
                            continue
                        }
                    }
                    // Fallback: random char, verify pinyin uniqueness
                    for _ in 0..<20 {
                        if let randomChar = getRandomChineseChar() {
                            if normalizePinyin(pinyin(of: randomChar)) != correctPinyin {
                                distractors.append(randomChar)
                                break
                            }
                        }
                    }
                    break  // Avoid infinite loop
                }
                distractors = Array(distractors.prefix(3))

                // Deduplicate and ensure correct answer is unique
                var options = Array(Set(distractors + [correctText]))
                options.removeAll { $0 == correctText }
                // Double-check: remove any remaining same-pinyin distractors
                options.removeAll { $0 != correctText && normalizePinyin(pinyin(of: $0)) == correctPinyin }
                options = Array(options.prefix(3)) + [correctText]
                options.shuffle()
                guard let correctIndex = options.firstIndex(of: correctText), options.count == 4 else { continue }

                questions.append(QuizQuestion(
                    correctAnswer: correctText,
                    options: options,
                    correctIndex: correctIndex,
                    sourceItem: quizItem,
                    questionType: .pinyinToCharacter
                ))
            }
        }

        return questions.isEmpty ? nil : questions
    }

    // MARK: - Word Expansion

    /// Expands a single-character wrong answer into a multi-character word
    /// ~40% of the time, using the character database.
    private func expandToWord(_ item: WrongAnswerItem) -> WrongAnswerItem {
        guard item.correctText.count == 1 else { return item }
        // 40% chance to expand single char to a word
        guard Int.random(in: 0..<10) < 4 else { return item }

        let char = item.correctText
        let charPinyin = normalizePinyin(item.correctPinyin)

        // Find multi-char words containing this character
        var candidates: [(word: String, pinyin: String)] = []
        for (py, chars) in pinyinToChars {
            for ch in chars {
                if ch.count >= 2 && ch.count <= 4 && ch.contains(char) {
                    let wordPinyin = pinyin(of: ch)
                    candidates.append((ch, normalizePinyin(wordPinyin)))
                }
            }
        }

        // Also check the dedicated word list
        for word in commonMultiCharWords {
            if word.count >= 2 && word.count <= 4 && word.contains(char) {
                let wordPinyin = pinyin(of: word)
                let norm = normalizePinyin(wordPinyin)
                if !candidates.contains(where: { $0.word == word }) {
                    candidates.append((word, norm))
                }
            }
        }

        guard let picked = candidates.randomElement() else { return item }

        return WrongAnswerItem(
            id: item.id,
            correctText: picked.word,
            wrongText: item.wrongText,
            correctPinyin: picked.pinyin,
            wrongPinyin: item.wrongPinyin,
            errorType: item.errorType,
            sessionID: item.sessionID,
            timestamp: item.timestamp
        )
    }

    // MARK: - Pinyin Distractor Generation (Multi-Syllable)

    /// Generates multi-syllable pinyin distractors with strong phonetic interference.
    /// All distractors share structural similarity (same syllable count, partial syllable overlap).
    private func generateMultiSyllablePinyinDistractors(for pinyin: String, syllableCount: Int) -> [String] {
        var distractors: Set<String> = []
        let syllables = splitIntoSyllables(pinyin)

        // Strategy 1: Replace one syllable with a similar-sounding one (strongest distractor)
        for pos in 0..<syllables.count {
            let originalSyl = syllables[pos]
            // Get strong phonetic neighbors for this syllable
            let neighbors = generateStrongPhoneticNeighbors(for: originalSyl)
            for alt in neighbors.prefix(3) where alt != originalSyl {
                var newSyllables = syllables
                newSyllables[pos] = alt
                let candidate = newSyllables.joined()
                if candidate != pinyin {
                    distractors.insert(candidate)
                }
            }
        }

        // Strategy 2: Swap two syllables (e.g., "putao" → "taopu") — subtle but confusing
        if syllables.count >= 2 && distractors.count < 3 {
            for i in 0..<(syllables.count - 1) {
                for j in (i + 1)..<syllables.count where syllables[i] != syllables[j] {
                    var swapped = syllables
                    swapped.swapAt(i, j)
                    let candidate = swapped.joined()
                    if candidate != pinyin {
                        distractors.insert(candidate)
                    }
                }
            }
        }

        // Strategy 3: Keep first syllable, replace rest with plausible continuations
        if syllables.count >= 2 && distractors.count < 3 {
            let first = syllables[0]
            let commonContinuations = getCommonSyllableContinuations(for: first)
            for cont in commonContinuations.shuffled().prefix(4) {
                let candidate = first + cont
                if candidate.count == pinyin.count && candidate != pinyin {
                    distractors.insert(candidate)
                }
            }
        }

        // Strategy 4: Same-initial pattern — change finals but keep initials (mimics native speaker confusion)
        if distractors.count < 3 {
            let initials = syllables.compactMap { splitPinyin($0)?.initial }
            for _ in 0..<8 {
                var newSyllables: [String] = []
                for init_ in initials {
                    let finals = getRandomFinals(excluding: "")
                    if let final = finals.randomElement() {
                        newSyllables.append(init_ + final)
                    }
                }
                if newSyllables.count == syllables.count {
                    let candidate = newSyllables.joined()
                    if candidate != pinyin && candidate.count == pinyin.count {
                        distractors.insert(candidate)
                    }
                }
                if distractors.count >= 3 { break }
            }
        }

        // Strategy 5: Same-final pattern — change initials but keep finals
        if distractors.count < 3 {
            let finals = syllables.compactMap { splitPinyin($0)?.final }
            for _ in 0..<8 {
                var newSyllables: [String] = []
                for final in finals {
                    let initials = getRandomInitials(excluding: "")
                    if let init_ = initials.randomElement() {
                        newSyllables.append(init_ + final)
                    }
                }
                if newSyllables.count == syllables.count {
                    let candidate = newSyllables.joined()
                    if candidate != pinyin && candidate.count == pinyin.count {
                        distractors.insert(candidate)
                    }
                }
                if distractors.count >= 3 { break }
            }
        }

        return Array(distractors)
    }

    /// Generates strong single-syllable phonetic neighbors (same initial or same final).
    private func generateStrongPhoneticNeighbors(for syllable: String) -> [String] {
        var result: [String] = []
        guard let (initial, final) = splitPinyin(syllable) else { return [syllable] }

        // Same final, different initial (confusing: "ban" vs "pan")
        let similarInitials = getSimilarInitials(initial)
        for init_ in similarInitials {
            result.append(init_ + final)
        }

        // Same initial, different final (confusing: "ban" vs "bang")
        let similarFinals = getSimilarFinals(final)
        for fin in similarFinals {
            result.append(initial + fin)
        }

        // Near-homophone initials (zh/z, ch/c, sh/s)
        let nearInitials = getNearHomophoneInitials(initial)
        for init_ in nearInitials {
            result.append(init_ + final)
        }

        // Near-homophone finals (an/ang, en/eng, in/ing)
        let nearFinals = getNearHomophoneFinals(final)
        for fin in nearFinals {
            result.append(initial + fin)
        }

        return result
    }

    /// Returns initials with similar articulation.
    private func getSimilarInitials(_ initial: String) -> [String] {
        let map: [String: [String]] = [
            "b": ["p", "m"], "p": ["b", "m"], "m": ["b", "p"],
            "d": ["t", "n", "l"], "t": ["d", "n", "l"], "n": ["d", "t", "l"], "l": ["d", "t", "n", "r"],
            "g": ["k", "h"], "k": ["g", "h"], "h": ["g", "k"],
            "j": ["q", "x"], "q": ["j", "x"], "x": ["j", "q"],
            "zh": ["ch", "sh"], "ch": ["zh", "sh"], "sh": ["zh", "ch", "r"], "r": ["sh", "l"],
            "z": ["c", "s"], "c": ["z", "s"], "s": ["z", "c"],
            "f": ["h"],
            "y": ["w"], "w": ["y"],
            "": ["y", "w"]
        ]
        return map[initial] ?? []
    }

    /// Returns near-homophone initials (zh↔z, ch↔c, sh↔s, n↔l, r↔l).
    private func getNearHomophoneInitials(_ initial: String) -> [String] {
        let map: [String: [String]] = [
            "zh": ["z", "j"], "z": ["zh", "j"],
            "ch": ["c", "q"], "c": ["ch", "q"],
            "sh": ["s", "x"], "s": ["sh", "x"],
            "n": ["l"], "l": ["n"],
            "r": ["l"], "f": ["h"], "h": ["f"]
        ]
        return map[initial] ?? []
    }

    /// Returns near-homophone finals (an↔ang, en↔eng, in↔ing).
    private func getNearHomophoneFinals(_ final: String) -> [String] {
        let map: [String: [String]] = [
            "an": ["ang"], "ang": ["an"],
            "en": ["eng"], "eng": ["en"],
            "in": ["ing"], "ing": ["in"],
            "ian": ["iang"], "iang": ["ian"],
            "uan": ["uang"], "uang": ["uan"],
            "ai": ["ei"], "ei": ["ai"],
            "ao": ["ou"], "ou": ["ao"]
        ]
        return map[final] ?? []
    }

    /// Returns common syllable continuations for a given first syllable.
    private func getCommonSyllableContinuations(for firstSyl: String) -> [String] {
        let commonPairs: [String: [String]] = [
            "pu": ["tao"], "tao": ["pu"],
            "bo": ["li", "luo", "tao"],
            "ma": ["ma", "mao", "mi"],
            "ji": ["qi", "jie", "xu"],
            "xi": ["gua", "yang", "hong"],
            "gu": ["jia", "shi", "dai"],
            "hu": ["die", "li", "luo"],
            "zhi": ["dao", "zhu", "hui"],
            "chu": ["tou", "fang", "xian"],
            "kai": ["shi", "xin", "guan"],
            "shu": ["fu", "cai", "ji"],
            "ying": ["tao", "xiong"],
            "mei": ["gui", "li", "hao"],
            "tian": ["kong", "qi", "mi"],
            "xiao": ["xi", "niao", "mai"],
            "da": ["jia", "hai", "lu"],
            "fa": ["xian", "ming", "da"],
            "ke": ["neng", "xue", "yi"],
            "xin": ["xian", "qing"],
            "li": ["mian", "hai", "xing"],
            "fang": ["bian", "jian", "shi"],
            "qing": ["chu", "tian", "nian"],
            "shi": ["jian", "qing", "jie"],
            "sheng": ["huo", "qi", "ming"],
            "cheng": ["shi", "gong", "ji"],
            "zhong": ["guo", "yao", "jian"],
            "dong": ["xi", "tian", "wu"],
            "nan": ["hai", "fang", "bei"],
        ]
        return commonPairs[firstSyl] ?? []
    }

    /// Returns random finals for distractor construction.
    private func getRandomFinals(excluding: String) -> [String] {
        let allFinals = ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng",
                         "i", "ia", "ie", "iao", "iu", "ian", "in", "iang", "ing", "iong",
                         "u", "ua", "uo", "uai", "ui", "uan", "un", "uang", "ong"]
        return allFinals.filter { $0 != excluding }
    }

    /// Returns random initials for distractor construction.
    private func getRandomInitials(excluding: String) -> [String] {
        let allInitials = ["b", "p", "m", "f", "d", "t", "n", "l",
                           "g", "k", "h", "j", "q", "x",
                           "zh", "ch", "sh", "r", "z", "c", "s",
                           "y", "w"]
        return allInitials.filter { $0 != excluding }
    }

    /// Splits a concatenated pinyin string into individual syllables.
    private func splitIntoSyllables(_ pinyin: String) -> [String] {
        var result: [String] = []
        var remaining = pinyin
        let initials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l",
                        "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"]

        while !remaining.isEmpty {
            var matched = false
            for initial in initials {
                if remaining.hasPrefix(initial) {
                    // Find the full syllable by looking for the next initial or end
                    let afterInit = String(remaining.dropFirst(initial.count))
                    var sylLen = initial.count
                    // Look ahead for next initial boundary
                    var foundBoundary = afterInit.count
                    for nextInit in initials {
                        if let range = afterInit.range(of: nextInit), !range.isEmpty {
                            let pos = afterInit.distance(from: afterInit.startIndex, to: range.lowerBound)
                            if pos < foundBoundary && pos > 0 {
                                foundBoundary = pos
                            }
                        }
                    }
                    sylLen += foundBoundary
                    let syl = String(remaining.prefix(sylLen))
                    result.append(syl)
                    remaining = String(remaining.dropFirst(sylLen))
                    matched = true
                    break
                }
            }
            if !matched {
                // Zero-initial syllable: take until next initial
                var foundBoundary = remaining.count
                for nextInit in initials {
                    if let range = remaining.range(of: nextInit), !range.isEmpty {
                        let pos = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
                        if pos < foundBoundary && pos > 0 {
                            foundBoundary = pos
                        }
                    }
                }
                let syl = String(remaining.prefix(foundBoundary))
                result.append(syl)
                remaining = String(remaining.dropFirst(foundBoundary))
            }
        }
        return result
    }

    // MARK: - Multi-Character Word Distractors

    /// Generates multi-character word distractors with strong visual and phonetic interference.
    /// All distractors share structural similarity (same length, partial character overlap).
    private func generateMultiCharWordDistractors(for word: String, correctPinyin: String, charCount: Int) -> [String] {
        var distractors: Set<String> = []
        let chars = Array(word)
        let normalizedPinyin = normalizePinyin(correctPinyin)

        // Strategy 1 (STRONGEST): Keep N-1 characters, replace one with a similar-pinyin char
        for i in 0..<charCount {
            let char = String(chars[i])
            let charPy = normalizePinyin(pinyin(of: char))
            // Get characters with VERY similar pinyin (same syllable, different tone; or same initial)
            let replacements = getStrongCharacterReplacements(for: char, pinyin: charPy, count: 5)
            for alt in replacements where alt != char && alt.count == 1 {
                var newChars = chars
                newChars[i] = Character(alt)
                let candidate = String(newChars)
                if candidate != word {
                    distractors.insert(candidate)
                }
            }
        }

        // Strategy 2: Use real words that share one character with the target
        if distractors.count < 3 {
            for (i, char) in chars.enumerated() {
                let sharedChar = String(char)
                let sameFirstWords = commonMultiCharWords.filter {
                    $0.count == charCount && $0 != word && $0.contains(sharedChar)
                }
                distractors.formUnion(sameFirstWords.shuffled().prefix(2))
                if distractors.count >= 3 { break }
            }
        }

        // Strategy 3: Words where each character has similar pinyin pattern to original
        if distractors.count < 3 {
            let pinyinSyllables = splitIntoSyllables(normalizedPinyin)
            for _ in 0..<10 {
                var candidate = ""
                for (idx, syl) in pinyinSyllables.enumerated() {
                    // Get characters with same pinyin as each syllable
                    if let homophones = pinyinToChars[syl], !homophones.isEmpty {
                        var filtered = homophones.filter { $0.count == 1 }
                        // Prefer different character from the original
                        if idx < chars.count {
                            filtered.removeAll { String($0) == String(chars[idx]) }
                        }
                        if let pick = filtered.randomElement() {
                            candidate += pick
                        } else if let any = homophones.randomElement(), any.count == 1 {
                            candidate += any
                        }
                    }
                }
                if candidate.count == charCount && candidate != word {
                    distractors.insert(candidate)
                }
                if distractors.count >= 3 { break }
            }
        }

        // Strategy 4: Near-homophone substitution — change one char to a visually similar or near-pinyin char
        if distractors.count < 3 {
            for i in 0..<charCount {
                let char = String(chars[i])
                let charPy = normalizePinyin(pinyin(of: char))
                // Get characters with near-homophone pinyin (zh↔z, ch↔c, sh↔s, n↔l)
                let nearChars = getNearHomophoneCharacters(for: charPy)
                for alt in nearChars.shuffled().prefix(4) where alt != char && alt.count == 1 {
                    var newChars = chars
                    newChars[i] = Character(alt)
                    let candidate = String(newChars)
                    if candidate != word {
                        distractors.insert(candidate)
                    }
                }
                if distractors.count >= 3 { break }
            }
        }

        // Strategy 5: Same-initial-character, different second character (or vice versa)
        if distractors.count < 3 && charCount >= 2 {
            // Keep first, find plausible second character
            let firstChar = String(chars[0])
            let firstPy = normalizePinyin(pinyin(of: firstChar))
            if let sharingWords = findWordsStartingWith(firstChar, length: charCount) {
                distractors.formUnion(sharingWords.shuffled().prefix(3))
            }

            // Find words with similar first-syllable
            if distractors.count < 3, let altChars = pinyinToChars[firstPy] {
                for alt in altChars.shuffled().prefix(3) where alt != firstChar && alt.count == 1 {
                    let altWord = alt + String(chars.dropFirst())
                    if altWord != word && altWord.count == charCount {
                        distractors.insert(altWord)
                    }
                }
            }
        }

        // Strategy 6: Real words with similar pinyin pattern (same initials or finals)
        if distractors.count < 3 {
            let wordSyllables = splitIntoSyllables(normalizedPinyin)
            let wordInitials = wordSyllables.compactMap { splitPinyin($0)?.initial }
            let wordFinals = wordSyllables.compactMap { splitPinyin($0)?.final }

            for candidateWord in commonMultiCharWords.shuffled().prefix(20) {
                guard candidateWord.count == charCount && candidateWord != word else { continue }
                let candPinyin = normalizePinyin(pinyin(of: candidateWord))
                let candSyllables = splitIntoSyllables(candPinyin)
                guard candSyllables.count == wordSyllables.count else { continue }

                // Count how many initials or finals match
                var matchScore = 0
                for idx in 0..<candSyllables.count {
                    let candParts = splitPinyin(candSyllables[idx])
                    if idx < wordInitials.count && candParts?.initial == wordInitials[idx] { matchScore += 1 }
                    if idx < wordFinals.count && candParts?.final == wordFinals[idx] { matchScore += 1 }
                }
                // Only use words with partial phonetic similarity
                if matchScore >= 1 {
                    distractors.insert(candidateWord)
                }
                if distractors.count >= 3 { break }
            }
        }

        return Array(distractors)
    }

    /// Returns strong character replacements: same pinyin (homophones), then near-pinyin chars.
    private func getStrongCharacterReplacements(for character: String, pinyin: String, count: Int) -> [String] {
        var result: [String] = []

        // Priority 1: Exact homophones (same pinyin, different character)
        if let homophones = pinyinToChars[pinyin] {
            let others = homophones.filter { $0 != character && $0.count == 1 }
            result.append(contentsOf: others.shuffled().prefix(count))
        }

        // Priority 2: Same initial, different final → different pinyin but similar sound
        if result.count < count, let (initial, _) = splitPinyin(pinyin) {
            let similarFinals = getSimilarFinals("") + getNearHomophoneFinals("")
            for final in similarFinals.shuffled().prefix(10) {
                let altPinyin = initial + final
                if let chars = pinyinToChars[altPinyin] {
                    for ch in chars where ch.count == 1 && !result.contains(ch) && ch != character {
                        result.append(ch)
                        if result.count >= count { break }
                    }
                }
                if result.count >= count { break }
            }
        }

        // Priority 3: Same final, different initial
        if result.count < count, let (_, final) = splitPinyin(pinyin), !final.isEmpty {
            let similarInitials = getSimilarInitials("") + getNearHomophoneInitials("")
            for init_ in similarInitials.shuffled().prefix(10) {
                let altPinyin = init_ + final
                if let chars = pinyinToChars[altPinyin] {
                    for ch in chars where ch.count == 1 && !result.contains(ch) && ch != character {
                        result.append(ch)
                        if result.count >= count { break }
                    }
                }
                if result.count >= count { break }
            }
        }

        return result
    }

    /// Returns characters with near-homophone pinyin (zh↔z, ch↔c, sh↔s, n↔l territory).
    private func getNearHomophoneCharacters(for pinyin: String) -> [String] {
        var result: [String] = []
        guard let (initial, final) = splitPinyin(pinyin) else { return result }

        let nearInitials = getNearHomophoneInitials(initial)
        for init_ in nearInitials {
            let altPinyin = init_ + final
            if let chars = pinyinToChars[altPinyin] {
                result.append(contentsOf: chars.filter { $0.count == 1 })
            }
        }

        let nearFinals = getNearHomophoneFinals(final)
        for fin in nearFinals {
            let altPinyin = initial + fin
            if let chars = pinyinToChars[altPinyin] {
                result.append(contentsOf: chars.filter { $0.count == 1 })
            }
        }

        return result
    }

    /// Finds real words starting with the given character.
    private func findWordsStartingWith(_ firstChar: String, length: Int) -> [String]? {
        let matches = commonMultiCharWords.filter {
            $0.count == length && $0.hasPrefix(firstChar)
        }
        return matches.isEmpty ? nil : matches
    }

    /// Returns a random word of the specified length.
    private func getRandomWord(length: Int) -> String? {
        let candidates = commonMultiCharWords.filter { $0.count == length }
        return candidates.randomElement()
    }

    // MARK: - Common Multi-Character Words for Distractors

    /// Database of common Chinese words (2-4 characters) used for distractor generation.
    private let commonMultiCharWords: [String] = [
        // 2-character words
        "我们", "他们", "你们", "自己", "大家", "什么", "怎么", "这样", "那样", "可以",
        "因为", "所以", "但是", "虽然", "如果", "而且", "或者", "不过", "只是", "还是",
        "已经", "正在", "将要", "曾经", "一直", "经常", "马上", "立刻", "忽然", "终于",
        "时候", "地方", "东西", "事情", "问题", "方法", "结果", "原因", "关系", "作用",
        "国家", "社会", "世界", "生活", "工作", "学习", "研究", "发展", "变化", "提高",
        "开始", "继续", "完成", "实现", "成功", "失败", "进步", "努力", "坚持", "帮助",
        "重要", "需要", "应该", "必须", "能够", "可能", "愿意", "希望", "觉得", "认为",
        "知道", "明白", "理解", "掌握", "熟悉", "了解", "发现", "注意", "关心", "重视",
        "中国", "美国", "日本", "北京", "上海", "广州", "深圳", "杭州", "南京", "成都",
        "老师", "学生", "同学", "朋友", "家人", "父母", "孩子", "先生", "女士", "领导",
        "颜色", "声音", "味道", "形状", "大小", "高低", "远近", "快慢", "轻重", "冷热",
        "春天", "夏天", "秋天", "冬天", "早晨", "中午", "晚上", "今天", "明天", "昨天",
        "苹果", "香蕉", "西瓜", "葡萄", "草莓", "橘子", "芒果", "柠檬", "桃子", "樱桃",
        "电脑", "手机", "电视", "电话", "网络", "软件", "程序", "数据", "信息", "技术",
        "音乐", "电影", "图书", "报纸", "杂志", "新闻", "故事", "笑话", "游戏", "运动",
        "医院", "学校", "商店", "银行", "公园", "机场", "车站", "酒店", "餐厅", "超市",
        "动物", "植物", "花朵", "树木", "河流", "山脉", "海洋", "天空", "大地", "太阳",
        "眼睛", "耳朵", "嘴巴", "鼻子", "头发", "手臂", "腿脚", "心脏", "大脑", "身体",
        "安全", "危险", "健康", "幸福", "快乐", "悲伤", "愤怒", "害怕", "紧张", "轻松",
        "比赛", "考试", "表演", "展览", "会议", "活动", "节日", "庆祝", "旅行", "参观",
        "葡萄", "蝴蝶", "蜻蜓", "蜘蛛", "蚂蚁", "蜜蜂", "骆驼", "熊猫", "孔雀", "鹦鹉",
        "葡萄", "玻璃", "琵琶", "枇杷", "蘑菇", "萝卜", "薄荷", "茉莉", "玫瑰", "牡丹",
        // 3-character words
        "为什么", "怎么样", "越来越", "差不多", "基本上", "大部分", "有时候", "不一定",
        "计算机", "互联网", "小学生", "中学生", "大学生", "图书馆", "电影院", "动物园",
        "巧克力", "冰淇淋", "西红柿", "马铃薯", "向日葵", "蒲公英", "含羞草", "仙人掌",
        // 4-character words
        "各种各样", "丰富多彩", "兴高采烈", "小心翼翼", "不知不觉", "自言自语",
        "千山万水", "万紫千红", "鸟语花香", "春暖花开", "秋高气爽", "冰天雪地",
    ]

    /// Records a completed quiz session (adds to history only, does NOT advance level).
    /// Automatically deduplicates by session ID.
    /// Call `advanceLevel(coinsEarned:)` separately to mark a level as passed.
    func recordQuizSession(_ session: QuizSession) {
        // Deduplicate: if a session with the same ID already exists, update it instead of appending
        if let existingIndex = quizProgress.sessionHistory.firstIndex(where: { $0.id == session.id }) {
            quizProgress.sessionHistory[existingIndex] = session
        } else {
            quizProgress.sessionHistory.append(session)
        }
        saveQuizProgress()
    }

    /// Marks the current level as passed, advances to the next level, and awards coins.
    /// - Parameters:
    ///   - coinsEarned: Number of coins to award (0 for basic success, 3+ for complete victory).
    ///   - isCompleteVictory: Whether this was a complete victory (>= 90% score).
    func advanceLevel(coinsEarned: Int, isCompleteVictory: Bool = false) {
        quizProgress.totalLevelsCompleted += 1

        // Track consecutive complete victories
        if isCompleteVictory {
            quizProgress.consecutiveCompleteVictories += 1
        } else {
            quizProgress.consecutiveCompleteVictories = 0
        }

        var totalCoins = coinsEarned
        if coinsEarned > 0 {
            RewardManager.shared.coins += coinsEarned
        }

        // Consecutive victory bonus: +1 coin per consecutive complete victory
        if isCompleteVictory && DeveloperSettingsManager.shared.effectiveConsecutiveVictoryBonusEnabled {
            let streak = quizProgress.consecutiveCompleteVictories
            if streak > 1 {
                let bonus = streak  // streak 2 → +2, streak 3 → +3, etc.
                RewardManager.shared.coins += bonus
                totalCoins += bonus
            }
        }

        // Milestone bonuses still apply (every 10/100 levels)
        let level = quizProgress.totalLevelsCompleted
        if level % 10 == 0 {
            RewardManager.shared.coins += 20
            totalCoins += 20
        }
        if level % 100 == 0 {
            RewardManager.shared.coins += 50
            totalCoins += 50
        }

        // Update the session's coinsEarned to reflect total (for history display)
        if let lastSession = quizProgress.sessionHistory.last {
            lastSession.coinsEarned = totalCoins
        }

        saveQuizProgress()
    }

    /// Returns the current consecutive complete victory streak.
    var consecutiveCompleteVictories: Int {
        return quizProgress.consecutiveCompleteVictories
    }

    /// Updates consecutive victory tracking without advancing a level.
    /// Called when a quiz session completes to immediately update the streak.
    func recordQuizResult(isCompleteVictory: Bool) {
        if isCompleteVictory {
            quizProgress.consecutiveCompleteVictories += 1
        } else {
            quizProgress.consecutiveCompleteVictories = 0
        }
        saveQuizProgress()
    }

    /// Returns the total number of completed levels.
    var totalLevelsCompleted: Int {
        return quizProgress.totalLevelsCompleted
    }

    /// Sets the total number of completed levels (for developer debugging).
    func setTotalLevelsCompleted(_ count: Int) {
        quizProgress.totalLevelsCompleted = max(0, count)
        if count == 0 {
            quizProgress.sessionHistory = []
        }
        saveQuizProgress()
    }

    // MARK: - Pinyin Utilities

    /// Converts Chinese text to pinyin using CFStringTransform.
    private func pinyin(of text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        return (mutable as String).lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// Public: Normalizes a raw pinyin string (strips tone numbers).
    func normalizedPinyin(for rawPinyin: String) -> String {
        return normalizePinyin(rawPinyin)
    }

    /// Normalizes pinyin: strips tone marks (diacritics and tone numbers), keeps lowercase letters.
    private func normalizePinyin(_ pinyin: String) -> String {
        var result = pinyin
        // Remove tone numbers (1-5)
        for i in 1...5 {
            result = result.replacingOccurrences(of: "\(i)", with: "")
        }
        // Strip diacritics (ā→a, ǎ→a, etc.)
        result = result.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en"))
        return result.lowercased()
    }

    /// Extracts the tone number from pinyin string (works with both diacritic and numeric forms).
    private func extractTone(_ pinyin: String) -> Int {
        // First check digit tones (1-5)
        for i in 1...5 {
            if pinyin.contains("\(i)") {
                return i
            }
        }
        // Then check diacritic tones
        return extractToneFromDiacritic(pinyin)
    }

    /// Generates pinyin distractors with similar pronunciation.
    private func generatePinyinDistractors(for pinyin: String) -> [String] {
        var distractors: Set<String> = []
        let normalized = normalizePinyin(pinyin)

        guard let (initial, final) = splitPinyin(normalized) else { return [] }

        // Strategy 1: Same final, different (similar) initial — "ban" → "pan", "man"
        let simInitials = getSimilarInitials(initial)
        for altInit in simInitials {
            let candidate = altInit + final
            if isValidSyllable(candidate) && candidate != normalized {
                distractors.insert(candidate)
            }
        }

        // Strategy 2: Same initial, different (similar) final — "ban" → "bang", "ben"
        let simFinals = getSimilarFinals(final)
        for altFinal in simFinals {
            let candidate = initial + altFinal
            if isValidSyllable(candidate) && candidate != normalized {
                distractors.insert(candidate)
            }
        }

        // Strategy 3: Near-homophone initials (zh↔z, ch↔c, sh↔s, n↔l)
        let nearInits = getNearHomophoneInitials(initial)
        for altInit in nearInits {
            let candidate = altInit + final
            if isValidSyllable(candidate) && candidate != normalized {
                distractors.insert(candidate)
            }
        }

        // Strategy 4: Near-homophone finals (an↔ang, en↔eng, in↔ing)
        let nearFins = getNearHomophoneFinals(final)
        for altFinal in nearFins {
            let candidate = initial + altFinal
            if isValidSyllable(candidate) && candidate != normalized {
                distractors.insert(candidate)
            }
        }

        // Strategy 5: Structured fill — use same-initial-different-final with common finals
        if distractors.count < 3 {
            let allFinals = ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng",
                             "i", "ia", "ie", "iao", "iu", "ian", "in", "iang", "ing", "iong",
                             "u", "ua", "uo", "uai", "ui", "uan", "un", "uang", "ong"]
            for fin in allFinals.shuffled() where fin != final {
                let candidate = initial + fin
                if isValidSyllable(candidate) && candidate != normalized {
                    distractors.insert(candidate)
                    if distractors.count >= 3 { break }
                }
            }
        }

        // Strategy 6: If still not enough, use all-initial swap with same final
        if distractors.count < 3 {
            let allInitials = ["b", "p", "m", "f", "d", "t", "n", "l",
                               "g", "k", "h", "j", "q", "x",
                               "zh", "ch", "sh", "r", "z", "c", "s", "y", "w"]
            for init_ in allInitials.shuffled() where init_ != initial && !simInitials.contains(init_) {
                let candidate = init_ + final
                if isValidSyllable(candidate) && candidate != normalized {
                    distractors.insert(candidate)
                    if distractors.count >= 3 { break }
                }
            }
        }

        return Array(distractors)
    }

    /// Checks if a candidate syllable is valid (exists in the pinyin-to-char database).
    private func isValidSyllable(_ syllable: String) -> Bool {
        return pinyinToChars[syllable] != nil
    }

    /// Splits a pinyin syllable into initial and final.
    private func splitPinyin(_ pinyin: String) -> (initial: String, final: String)? {
        let initials = ["zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l",
                        "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w"]

        for initial in initials {
            if pinyin.hasPrefix(initial) {
                let final = String(pinyin.dropFirst(initial.count))
                return (initial, final)
            }
        }
        // Zero initial
        return ("", pinyin)
    }

    /// Returns similar finals for distractor generation.
    private func getSimilarFinals(_ final: String) -> [String] {
        let similarGroups: [[String]] = [
            ["an", "ang"],
            ["en", "eng"],
            ["in", "ing"],
            ["ian", "iang"],
            ["uan", "uang"],
            ["ai", "ei"],
            ["ao", "ou"],
            ["ia", "ie"],
            ["ua", "uo"],
            ["iao", "iou"],
            ["uai", "uei"],
            ["an", "en"],
            ["ang", "eng"],
            ["ong", "eng"],
            ["un", "ong"],
            ["ui", "ei"],
            ["iu", "ou"]
        ]

        for group in similarGroups {
            if group.contains(final) {
                return group.filter { $0 != final }
            }
        }
        return []
    }

    /// Generates a random pinyin string of the given syllable count.
    private func generateRandomPinyin(length: Int = 1) -> String {
        let syllables = ["ba", "ma", "da", "ta", "na", "la", "ga", "ka", "ha",
                         "ji", "qi", "xi", "zhi", "chi", "shi", "ri", "zi", "ci", "si"]
        var result: [String] = []
        for _ in 0..<length {
            result.append(syllables.randomElement() ?? "ba")
        }
        return result.joined()
    }

    // MARK: - Tone Mark Utilities

    /// Generates single-syllable pinyin distractors with random tone marks applied.
    private func generateTonedPinyinDistractors(for normalized: String, correctToned: String) -> [String] {
        let raw = generatePinyinDistractors(for: normalized)
        // Extract the correct tone from the toned pinyin to avoid matching it accidentally
        let correctTone = extractToneFromDiacritic(correctToned)
        return raw.map { applyTone(to: $0, tone: randomTone(avoiding: correctTone)) }
    }

    /// Adds random tone marks to each syllable in a multi-syllable pinyin string.
    private func addRandomTonesToSyllables(_ pinyin: String) -> String {
        let syllables = splitIntoSyllables(pinyin)
        return syllables.map { applyTone(to: $0, tone: Int.random(in: 1...4)) }.joined()
    }

    /// Applies a tone diacritic to the main vowel of a pinyin syllable.
    /// Tone: 1=flat(ā), 2=rising(á), 3=dipping(ǎ), 4=falling(à), 0=neutral.
    private func applyTone(to syllable: String, tone: Int) -> String {
        guard tone >= 1 && tone <= 4 else { return syllable }

        // Find the main vowel to mark (a/e first, then ou, then last vowel)
        let vowelPriority: [Character] = ["a", "e", "i", "o", "u", "ü", "v"]
        var chars = Array(syllable)
        var markIndex: Int?

        // First pass: look for 'a' or 'e'
        for (i, ch) in chars.enumerated() {
            if ch == "a" || ch == "e" {
                markIndex = i
                break
            }
        }

        // Second pass: look for 'ou' combo → mark 'o'
        if markIndex == nil {
            for i in 0..<(chars.count - 1) {
                if chars[i] == "o" && chars[i + 1] == "u" {
                    markIndex = i
                    break
                }
            }
        }

        // Third pass: mark the last vowel
        if markIndex == nil {
            for i in (0..<chars.count).reversed() {
                let ch = chars[i]
                if vowelPriority.contains(ch) {
                    markIndex = i
                    break
                }
            }
        }

        guard let idx = markIndex else { return syllable }

        let vowel = chars[idx]
        if let toned = tonedVowel(vowel, tone: tone) {
            chars[idx] = toned
        }

        return String(chars)
    }

    /// Returns the tone-marked vowel character.
    private func tonedVowel(_ vowel: Character, tone: Int) -> Character? {
        let map: [Character: [Character]] = [
            "a": ["a", "ā", "á", "ǎ", "à"],
            "e": ["e", "ē", "é", "ě", "è"],
            "i": ["i", "ī", "í", "ǐ", "ì"],
            "o": ["o", "ō", "ó", "ǒ", "ò"],
            "u": ["u", "ū", "ú", "ǔ", "ù"],
            "ü": ["ü", "ǖ", "ǘ", "ǚ", "ǜ"],
            "v": ["ü", "ǖ", "ǘ", "ǚ", "ǜ"]
        ]
        guard let variants = map[vowel], tone >= 0 && tone <= 4 else { return nil }
        return variants[tone]
    }

    /// Extracts tone number (1-4) from a tone-marked pinyin syllable. Returns 0 for neutral.
    private func extractToneFromDiacritic(_ syllable: String) -> Int {
        let toneMap: [Character: Int] = [
            "ā": 1, "á": 2, "ǎ": 3, "à": 4,
            "ē": 1, "é": 2, "ě": 3, "è": 4,
            "ī": 1, "í": 2, "ǐ": 3, "ì": 4,
            "ō": 1, "ó": 2, "ǒ": 3, "ò": 4,
            "ū": 1, "ú": 2, "ǔ": 3, "ù": 4,
            "ǖ": 1, "ǘ": 2, "ǚ": 3, "ǜ": 4
        ]
        for ch in syllable {
            if let t = toneMap[ch] { return t }
        }
        return 0
    }

    /// Returns a random tone (1-4) avoiding a specific tone.
    private func randomTone(avoiding: Int) -> Int {
        let candidates = [1, 2, 3, 4].filter { $0 != avoiding }
        return candidates.randomElement() ?? 1
    }

    /// Generates character distractors with similar pronunciation.
    private func generateCharacterDistractors(for character: String, correctPinyin: String) -> [String] {
        var distractors: Set<String> = []
        let normalized = normalizePinyin(correctPinyin)

        // Strategy 1 (STRONGEST): Same pinyin, different character (homophones)
        if let homophones = pinyinToChars[normalized] {
            let others = homophones.filter { $0 != character && $0.count == 1 }
            distractors.formUnion(others.shuffled().prefix(5))
        }

        // Strategy 2: Same final, different initial (e.g., 马 mǎ → 打 dǎ, 把 bǎ)
        if distractors.count < 4, let (initial, final) = splitPinyin(normalized) {
            let simInitials = getSimilarInitials(initial) + getNearHomophoneInitials(initial)
            for altInit in simInitials.shuffled() {
                let altPinyin = altInit + final
                if let chars = pinyinToChars[altPinyin] {
                    for ch in chars where ch != character && ch.count == 1 {
                        distractors.insert(ch)
                        if distractors.count >= 4 { break }
                    }
                }
                if distractors.count >= 4 { break }
            }
        }

        // Strategy 3: Same initial, different final (e.g., 马 mǎ → 买 mǎi, 慢 màn)
        if distractors.count < 4, let (initial, final) = splitPinyin(normalized) {
            let simFinals = getSimilarFinals(final) + getNearHomophoneFinals(final)
            for altFinal in simFinals.shuffled() {
                let altPinyin = initial + altFinal
                if let chars = pinyinToChars[altPinyin] {
                    for ch in chars where ch != character && ch.count == 1 {
                        distractors.insert(ch)
                        if distractors.count >= 4 { break }
                    }
                }
                if distractors.count >= 4 { break }
            }
        }

        // Strategy 4: Near-homophone — zh↔z, ch↔c, sh↔s, n↔l, r↔l (e.g., 是 shì → 四 sì)
        if distractors.count < 4, let (initial, final) = splitPinyin(normalized) {
            let nearInits = getNearHomophoneInitials(initial)
            for altInit in nearInits.shuffled() {
                let altPinyin = altInit + final
                if let chars = pinyinToChars[altPinyin] {
                    for ch in chars where ch != character && ch.count == 1 {
                        distractors.insert(ch)
                        if distractors.count >= 4 { break }
                    }
                }
                if distractors.count >= 4 { break }
            }
        }

        // Strategy 5: Near-homophone finals — an↔ang, en↔eng, in↔ing
        if distractors.count < 4, let (initial, final) = splitPinyin(normalized) {
            let nearFins = getNearHomophoneFinals(final)
            for altFinal in nearFins.shuffled() {
                let altPinyin = initial + altFinal
                if let chars = pinyinToChars[altPinyin] {
                    for ch in chars where ch != character && ch.count == 1 {
                        distractors.insert(ch)
                        if distractors.count >= 4 { break }
                    }
                }
                if distractors.count >= 4 { break }
            }
        }

        return Array(distractors).shuffled()
    }

    /// Returns a random common Chinese character.
    private func getRandomChineseChar() -> String? {
        let allChars = pinyinToChars.values.flatMap { $0 }
        return allChars.randomElement()
    }

    // MARK: - Pinyin Database

    /// Builds a database mapping pinyin to common Chinese characters.
    private func buildPinyinDatabase() {
        // Common Chinese characters with their pinyin (comprehensive list)
        let charPinyinPairs: [(String, String)] = [
            // a
            ("啊", "a"), ("阿", "a"),
            // ai
            ("爱", "ai"), ("矮", "ai"), ("挨", "ai"), ("癌", "ai"), ("碍", "ai"), ("哀", "ai"),
            // an
            ("安", "an"), ("按", "an"), ("暗", "an"), ("案", "an"), ("岸", "an"), ("俺", "an"),
            // ang
            ("昂", "ang"),
            // ao
            ("奥", "ao"), ("傲", "ao"), ("凹", "ao"), ("熬", "ao"), ("袄", "ao"), ("澳", "ao"),
            // ba
            ("八", "ba"), ("把", "ba"), ("爸", "ba"), ("吧", "ba"), ("巴", "ba"), ("拔", "ba"), ("霸", "ba"), ("罢", "ba"),
            // bai
            ("白", "bai"), ("百", "bai"), ("败", "bai"), ("拜", "bai"), ("摆", "bai"), ("柏", "bai"),
            // ban
            ("班", "ban"), ("办", "ban"), ("半", "ban"), ("般", "ban"), ("板", "ban"), ("版", "ban"), ("搬", "ban"), ("扮", "ban"), ("伴", "ban"),
            // bang
            ("帮", "bang"), ("邦", "bang"), ("绑", "bang"), ("棒", "bang"), ("傍", "bang"),
            // bao
            ("报", "bao"), ("包", "bao"), ("保", "bao"), ("宝", "bao"), ("暴", "bao"), ("抱", "bao"), ("薄", "bao"), ("饱", "bao"), ("爆", "bao"),
            // bei
            ("北", "bei"), ("被", "bei"), ("备", "bei"), ("背", "bei"), ("杯", "bei"), ("倍", "bei"), ("悲", "bei"), ("碑", "bei"), ("贝", "bei"),
            // ben
            ("本", "ben"), ("奔", "ben"), ("笨", "ben"),
            // beng
            ("蹦", "beng"), ("崩", "beng"),
            // bi
            ("比", "bi"), ("笔", "bi"), ("必", "bi"), ("币", "bi"), ("毕", "bi"), ("闭", "bi"), ("避", "bi"), ("壁", "bi"), ("臂", "bi"), ("逼", "bi"), ("鼻", "bi"),
            // bian
            ("边", "bian"), ("变", "bian"), ("便", "bian"), ("遍", "bian"), ("编", "bian"), ("辩", "bian"), ("鞭", "bian"),
            // biao
            ("表", "biao"), ("标", "biao"), ("彪", "biao"),
            // bie
            ("别", "bie"),
            // bin
            ("宾", "bin"), ("滨", "bin"),
            // bing
            ("并", "bing"), ("病", "bing"), ("兵", "bing"), ("冰", "bing"), ("饼", "bing"), ("丙", "bing"),
            // bo
            ("波", "bo"), ("播", "bo"), ("博", "bo"), ("伯", "bo"), ("薄", "bo"), ("驳", "bo"), ("拨", "bo"),
            // bu
            ("不", "bu"), ("步", "bu"), ("部", "bu"), ("布", "bu"), ("补", "bu"), ("捕", "bu"),
            // ca
            ("擦", "ca"),
            // cai
            ("才", "cai"), ("财", "cai"), ("采", "cai"), ("彩", "cai"), ("菜", "cai"), ("猜", "cai"), ("裁", "cai"), ("材", "cai"),
            // can
            ("参", "can"), ("餐", "can"), ("残", "can"), ("惨", "can"), ("灿", "can"),
            // cang
            ("藏", "cang"), ("仓", "cang"), ("苍", "cang"),
            // cao
            ("草", "cao"), ("操", "cao"), ("槽", "cao"),
            // ce
            ("册", "ce"), ("侧", "ce"), ("策", "ce"), ("测", "ce"),
            // ceng
            ("曾", "ceng"), ("层", "ceng"),
            // cha
            ("查", "cha"), ("差", "cha"), ("茶", "cha"), ("察", "cha"), ("插", "cha"),
            // chai
            ("差", "chai"), ("拆", "chai"), ("柴", "chai"),
            // chan
            ("产", "chan"), ("长", "chang"), ("场", "chang"), ("常", "chang"), ("厂", "chang"), ("唱", "chang"), ("尝", "chang"), ("昌", "chang"),
            // chao
            ("超", "chao"), ("朝", "chao"), ("潮", "chao"), ("吵", "chao"), ("抄", "chao"),
            // che
            ("车", "che"), ("彻", "che"), ("撤", "che"),
            // chen
            ("陈", "chen"), ("沉", "chen"), ("晨", "chen"), ("称", "chen"), ("趁", "chen"), ("臣", "chen"), ("尘", "chen"),
            // cheng
            ("成", "cheng"), ("城", "cheng"), ("程", "cheng"), ("称", "cheng"), ("承", "cheng"), ("诚", "cheng"), ("乘", "cheng"), ("呈", "cheng"),
            // chi
            ("吃", "chi"), ("持", "chi"), ("尺", "chi"), ("迟", "chi"), ("池", "chi"), ("翅", "chi"), ("齿", "chi"), ("赤", "chi"),
            // chong
            ("重", "chong"), ("冲", "chong"), ("充", "chong"), ("虫", "chong"), ("崇", "chong"),
            // chou
            ("抽", "chou"), ("愁", "chou"), ("仇", "chou"), ("丑", "chou"), ("臭", "chou"),
            // chu
            ("出", "chu"), ("处", "chu"), ("初", "chu"), ("除", "chu"), ("楚", "chu"), ("础", "chu"), ("触", "chu"), ("储", "chu"),
            // chuai
            ("揣", "chuai"),
            // chuan
            ("传", "chuan"), ("船", "chuan"), ("穿", "chuan"), ("串", "chuan"), ("川", "chuan"),
            // chuang
            ("窗", "chuang"), ("创", "chuang"), ("床", "chuang"), ("闯", "chuang"),
            // chui
            ("吹", "chui"), ("垂", "chui"), ("锤", "chui"),
            // chun
            ("春", "chun"), ("纯", "chun"), ("唇", "chun"), ("醇", "chun"),
            // ci
            ("词", "ci"), ("次", "ci"), ("此", "ci"), ("辞", "ci"), ("刺", "ci"), ("磁", "ci"),
            // cong
            ("从", "cong"), ("聪", "cong"), ("丛", "cong"),
            // cou
            ("凑", "cou"),
            // cu
            ("粗", "cu"), ("促", "cu"), ("醋", "cu"),
            // cuan
            ("窜", "cuan"),
            // cui
            ("催", "cui"), ("脆", "cui"), ("翠", "cui"),
            // cun
            ("村", "cun"), ("存", "cun"), ("寸", "cun"),
            // cuo
            ("错", "cuo"), ("措", "cuo"),
            // da
            ("大", "da"), ("打", "da"), ("达", "da"), ("答", "da"), ("搭", "da"),
            // dai
            ("带", "dai"), ("代", "dai"), ("待", "dai"), ("戴", "dai"), ("袋", "dai"), ("贷", "dai"), ("逮", "dai"),
            // dan
            ("但", "dan"), ("单", "dan"), ("蛋", "dan"), ("淡", "dan"), ("担", "dan"), ("弹", "dan"), ("旦", "dan"), ("诞", "dan"),
            // dang
            ("当", "dang"), ("党", "dang"), ("档", "dang"), ("挡", "dang"),
            // dao
            ("到", "dao"), ("道", "dao"), ("导", "dao"), ("倒", "dao"), ("刀", "dao"), ("岛", "dao"), ("盗", "dao"), ("稻", "dao"),
            // de
            ("的", "de"), ("得", "de"), ("德", "de"),
            // deng
            ("等", "deng"), ("灯", "deng"), ("登", "deng"), ("邓", "deng"),
            // di
            ("地", "di"), ("第", "di"), ("低", "di"), ("底", "di"), ("敌", "di"), ("弟", "di"), ("帝", "di"), ("递", "di"), ("滴", "di"),
            // dian
            ("点", "dian"), ("电", "dian"), ("店", "dian"), ("典", "dian"), ("垫", "dian"), ("殿", "dian"),
            // diao
            ("调", "diao"), ("掉", "diao"), ("雕", "diao"), ("钓", "diao"),
            // die
            ("跌", "die"), ("叠", "die"), ("爹", "die"), ("碟", "die"),
            // ding
            ("定", "ding"), ("顶", "ding"), ("订", "ding"), ("丁", "ding"), ("盯", "ding"),
            // diu
            ("丢", "diu"),
            // dong
            ("动", "dong"), ("东", "dong"), ("冬", "dong"), ("懂", "dong"), ("洞", "dong"), ("冻", "dong"), ("董", "dong"),
            // dou
            ("都", "dou"), ("豆", "dou"), ("斗", "dou"), ("抖", "dou"), ("陡", "dou"),
            // du
            ("读", "du"), ("度", "du"), ("都", "du"), ("独", "du"), ("堵", "du"), ("赌", "du"), ("杜", "du"), ("肚", "du"), ("毒", "du"),
            // duan
            ("段", "duan"), ("短", "duan"), ("断", "duan"), ("端", "duan"), ("锻", "duan"),
            // dui
            ("对", "dui"), ("队", "dui"), ("堆", "dui"),
            // dun
            ("顿", "dun"), ("盾", "dun"), ("吨", "dun"), ("蹲", "dun"),
            // duo
            ("多", "duo"), ("夺", "duo"), ("朵", "duo"), ("躲", "duo"), ("堕", "duo"),
            // e
            ("饿", "e"), ("恶", "e"), ("额", "e"), ("鹅", "e"), ("俄", "e"), ("扼", "e"),
            // en
            ("恩", "en"),
            // er
            ("而", "er"), ("二", "er"), ("儿", "er"), ("耳", "er"),
            // fa
            ("发", "fa"), ("法", "fa"), ("罚", "fa"), ("伐", "fa"),
            // fan
            ("反", "fan"), ("饭", "fan"), ("翻", "fan"), ("范", "fan"), ("犯", "fan"), ("凡", "fan"), ("烦", "fan"), ("繁", "fan"),
            // fang
            ("放", "fang"), ("方", "fang"), ("房", "fang"), ("防", "fang"), ("访", "fang"), ("仿", "fang"), ("纺", "fang"),
            // fei
            ("飞", "fei"), ("非", "fei"), ("费", "fei"), ("肥", "fei"), ("废", "fei"), ("肺", "fei"), ("匪", "fei"),
            // fen
            ("分", "fen"), ("份", "fen"), ("粉", "fen"), ("纷", "fen"), ("奋", "fen"), ("愤", "fen"), ("坟", "fen"),
            // feng
            ("风", "feng"), ("封", "feng"), ("峰", "feng"), ("丰", "feng"), ("疯", "feng"), ("锋", "feng"), ("逢", "feng"), ("凤", "feng"),
            // fo
            ("佛", "fo"),
            // fou
            ("否", "fou"),
            // fu
            ("服", "fu"), ("夫", "fu"), ("父", "fu"), ("复", "fu"), ("福", "fu"), ("富", "fu"), ("副", "fu"), ("附", "fu"), ("负", "fu"), ("府", "fu"),
            // ga
            ("嘎", "ga"),
            // gai
            ("该", "gai"), ("改", "gai"), ("概", "gai"), ("盖", "gai"), ("钙", "gai"),
            // gan
            ("感", "gan"), ("干", "gan"), ("敢", "gan"), ("赶", "gan"), ("肝", "gan"), ("杆", "gan"), ("甘", "gan"),
            // gang
            ("刚", "gang"), ("钢", "gang"), ("港", "gang"), ("岗", "gang"), ("纲", "gang"),
            // gao
            ("高", "gao"), ("告", "gao"), ("搞", "gao"), ("稿", "gao"), ("糕", "gao"),
            // ge
            ("个", "ge"), ("歌", "ge"), ("格", "ge"), ("哥", "ge"), ("革", "ge"), ("隔", "ge"), ("阁", "ge"), ("鸽", "ge"),
            // gei
            ("给", "gei"),
            // gen
            ("根", "gen"), ("跟", "gen"),
            // geng
            ("更", "geng"), ("耕", "geng"), ("耿", "geng"),
            // gong
            ("工", "gong"), ("公", "gong"), ("功", "gong"), ("共", "gong"), ("供", "gong"), ("攻", "gong"), ("宫", "gong"), ("恭", "gong"),
            // gou
            ("狗", "gou"), ("够", "gou"), ("购", "gou"), ("构", "gou"), ("沟", "gou"), ("钩", "gou"),
            // gu
            ("故", "gu"), ("古", "gu"), ("股", "gu"), ("顾", "gu"), ("鼓", "gu"), ("骨", "gu"), ("姑", "gu"), ("谷", "gu"), ("孤", "gu"),
            // gua
            ("挂", "gua"), ("瓜", "gua"), ("刮", "gua"), ("寡", "gua"),
            // guai
            ("怪", "guai"), ("拐", "guai"),
            // guan
            ("关", "guan"), ("管", "guan"), ("观", "guan"), ("官", "guan"), ("馆", "guan"), ("冠", "guan"), ("惯", "guan"), ("灌", "guan"),
            // guang
            ("光", "guang"), ("广", "guang"), ("逛", "guang"),
            // gui
            ("归", "gui"), ("贵", "gui"), ("鬼", "gui"), ("规", "gui"), ("桂", "gui"), ("轨", "gui"), ("跪", "gui"),
            // gun
            ("滚", "gun"), ("棍", "gun"),
            // guo
            ("过", "guo"), ("国", "guo"), ("果", "guo"), ("锅", "guo"), ("郭", "guo"),
            // ha
            ("哈", "ha"),
            // hai
            ("还", "hai"), ("海", "hai"), ("害", "hai"), ("孩", "hai"),
            // han
            ("汉", "han"), ("含", "han"), ("喊", "han"), ("寒", "han"), ("韩", "han"), ("汗", "han"), ("旱", "han"),
            // hang
            ("行", "hang"), ("航", "hang"), ("杭", "hang"),
            // hao
            ("好", "hao"), ("号", "hao"), ("毫", "hao"), ("豪", "hao"), ("浩", "hao"), ("耗", "hao"),
            // he
            ("和", "he"), ("合", "he"), ("河", "he"), ("何", "he"), ("喝", "he"), ("核", "he"), ("贺", "he"), ("盒", "he"),
            // hei
            ("黑", "hei"),
            // hen
            ("很", "hen"), ("恨", "hen"), ("狠", "hen"),
            // heng
            ("横", "heng"), ("恒", "heng"), ("衡", "heng"),
            // hong
            ("红", "hong"), ("宏", "hong"), ("洪", "hong"), ("轰", "hong"), ("虹", "hong"),
            // hou
            ("后", "hou"), ("候", "hou"), ("厚", "hou"), ("猴", "hou"), ("喉", "hou"),
            // hu
            ("湖", "hu"), ("护", "hu"), ("互", "hu"), ("户", "hu"), ("呼", "hu"), ("虎", "hu"), ("胡", "hu"), ("忽", "hu"),
            // hua
            ("话", "hua"), ("花", "hua"), ("化", "hua"), ("画", "hua"), ("华", "hua"), ("划", "hua"),
            // huai
            ("坏", "huai"), ("怀", "huai"), ("淮", "huai"),
            // huan
            ("换", "huan"), ("欢", "huan"), ("环", "huan"), ("还", "huan"), ("缓", "huan"), ("患", "huan"), ("幻", "huan"),
            // huang
            ("黄", "huang"), ("皇", "huang"), ("慌", "huang"), ("晃", "huang"), ("煌", "huang"),
            // hui
            ("回", "hui"), ("会", "hui"), ("灰", "hui"), ("挥", "hui"), ("辉", "hui"), ("汇", "hui"), ("绘", "hui"), ("毁", "hui"),
            // hun
            ("婚", "hun"), ("混", "hun"), ("魂", "hun"), ("浑", "hun"),
            // huo
            ("火", "huo"), ("活", "huo"), ("或", "huo"), ("货", "huo"), ("获", "huo"), ("伙", "huo"), ("祸", "huo"),
            // ji
            ("机", "ji"), ("几", "ji"), ("记", "ji"), ("级", "ji"), ("计", "ji"), ("及", "ji"), ("极", "ji"), ("集", "ji"), ("急", "ji"), ("际", "ji"), ("技", "ji"), ("基", "ji"), ("既", "ji"), ("纪", "ji"), ("击", "ji"), ("积", "ji"), ("激", "ji"),
            // jia
            ("家", "jia"), ("加", "jia"), ("假", "jia"), ("价", "jia"), ("架", "jia"), ("甲", "jia"), ("驾", "jia"), ("嫁", "jia"),
            // jian
            ("见", "jian"), ("件", "jian"), ("间", "jian"), ("建", "jian"), ("检", "jian"), ("简", "jian"), ("减", "jian"), ("健", "jian"), ("坚", "jian"), ("渐", "jian"), ("剑", "jian"), ("尖", "jian"),
            // jiang
            ("将", "jiang"), ("讲", "jiang"), ("江", "jiang"), ("降", "jiang"), ("奖", "jiang"), ("姜", "jiang"), ("疆", "jiang"),
            // jiao
            ("教", "jiao"), ("交", "jiao"), ("叫", "jiao"), ("角", "jiao"), ("脚", "jiao"), ("较", "jiao"), ("焦", "jiao"), ("胶", "jiao"), ("郊", "jiao"), ("骄", "jiao"), ("娇", "jiao"),
            // jie
            ("接", "jie"), ("结", "jie"), ("解", "jie"), ("节", "jie"), ("界", "jie"), ("姐", "jie"), ("介", "jie"), ("借", "jie"), ("街", "jie"), ("阶", "jie"),
            // jin
            ("进", "jin"), ("金", "jin"), ("近", "jin"), ("今", "jin"), ("尽", "jin"), ("紧", "jin"), ("仅", "jin"), ("禁", "jin"), ("劲", "jin"), ("斤", "jin"),
            // jing
            ("经", "jing"), ("精", "jing"), ("京", "jing"), ("景", "jing"), ("静", "jing"), ("竟", "jing"), ("竞", "jing"), ("镜", "jing"), ("境", "jing"), ("警", "jing"),
            // jiong
            ("窘", "jiong"),
            // jiu
            ("就", "jiu"), ("九", "jiu"), ("酒", "jiu"), ("旧", "jiu"), ("久", "jiu"), ("救", "jiu"), ("纠", "jiu"), ("舅", "jiu"),
            // ju
            ("句", "ju"), ("具", "ju"), ("据", "ju"), ("举", "ju"), ("局", "ju"), ("剧", "ju"), ("聚", "ju"), ("距", "ju"), ("拒", "ju"), ("巨", "ju"), ("居", "ju"),
            // juan
            ("卷", "juan"), ("捐", "juan"), ("娟", "juan"),
            // jue
            ("觉", "jue"), ("决", "jue"), ("绝", "jue"), ("角", "jue"), ("掘", "jue"), ("爵", "jue"),
            // jun
            ("军", "jun"), ("均", "jun"), ("君", "jun"), ("俊", "jun"), ("菌", "jun"),
            // ka
            ("卡", "ka"), ("咖", "ka"),
            // kai
            ("开", "kai"), ("凯", "kai"), ("慨", "kai"),
            // kan
            ("看", "kan"), ("砍", "kan"), ("刊", "kan"), ("堪", "kan"),
            // kang
            ("抗", "kang"), ("康", "kang"), ("扛", "kang"),
            // kao
            ("考", "kao"), ("靠", "kao"), ("烤", "kao"),
            // ke
            ("可", "ke"), ("科", "ke"), ("课", "ke"), ("客", "ke"), ("刻", "ke"), ("克", "ke"), ("颗", "ke"), ("渴", "ke"), ("壳", "ke"),
            // ken
            ("肯", "ken"), ("恳", "ken"), ("啃", "ken"),
            // keng
            ("坑", "keng"),
            // kong
            ("空", "kong"), ("控", "kong"), ("孔", "kong"), ("恐", "kong"),
            // kou
            ("口", "kou"), ("扣", "kou"), ("寇", "kou"),
            // ku
            ("哭", "ku"), ("苦", "ku"), ("库", "ku"), ("裤", "ku"), ("酷", "ku"),
            // kua
            ("跨", "kua"), ("夸", "kua"), ("垮", "kua"),
            // kuai
            ("快", "kuai"), ("块", "kuai"), ("筷", "kuai"),
            // kuan
            ("宽", "kuan"), ("款", "kuan"),
            // kuang
            ("况", "kuang"), ("矿", "kuang"), ("框", "kuang"), ("狂", "kuang"), ("筐", "kuang"),
            // kui
            ("困", "kun"), ("捆", "kun"),
            // kuo
            ("扩", "kuo"), ("括", "kuo"), ("阔", "kuo"),
            // la
            ("拉", "la"), ("啦", "la"), ("辣", "la"), ("腊", "la"),
            // lai
            ("来", "lai"), ("赖", "lai"),
            // lan
            ("蓝", "lan"), ("兰", "lan"), ("栏", "lan"), ("烂", "lan"), ("篮", "lan"), ("览", "lan"), ("懒", "lan"),
            // lang
            ("浪", "lang"), ("郎", "lang"), ("狼", "lang"), ("朗", "lang"), ("廊", "lang"),
            // lao
            ("老", "lao"), ("劳", "lao"), ("牢", "lao"), ("捞", "lao"),
            // le
            ("了", "le"), ("乐", "le"), ("勒", "le"),
            // lei
            ("类", "lei"), ("雷", "lei"), ("累", "lei"), ("泪", "lei"), ("垒", "lei"),
            // leng
            ("冷", "leng"), ("棱", "leng"),
            // li
            ("里", "li"), ("力", "li"), ("理", "li"), ("利", "li"), ("立", "li"), ("离", "li"), ("例", "li"), ("历", "li"), ("李", "li"), ("礼", "li"), ("丽", "li"), ("励", "li"), ("粒", "li"),
            // lia
            ("俩", "lia"),
            // lian
            ("连", "lian"), ("联", "lian"), ("脸", "lian"), ("练", "lian"), ("链", "lian"), ("恋", "lian"), ("帘", "lian"),
            // liang
            ("两", "liang"), ("量", "liang"), ("亮", "liang"), ("辆", "liang"), ("凉", "liang"), ("良", "liang"), ("粮", "liang"),
            // liao
            ("了", "liao"), ("料", "liao"), ("疗", "liao"), ("聊", "liao"), ("辽", "liao"),
            // lie
            ("列", "lie"), ("烈", "lie"), ("裂", "lie"), ("猎", "lie"),
            // lin
            ("林", "lin"), ("临", "lin"), ("邻", "lin"), ("淋", "lin"), ("磷", "lin"),
            // ling
            ("领", "ling"), ("另", "ling"), ("令", "ling"), ("零", "ling"), ("灵", "ling"), ("龄", "ling"), ("铃", "ling"),
            // liu
            ("六", "liu"), ("流", "liu"), ("留", "liu"), ("刘", "liu"), ("柳", "liu"),
            // long
            ("龙", "long"), ("弄", "long"), ("隆", "long"), ("笼", "long"), ("聋", "long"),
            // lou
            ("楼", "lou"), ("漏", "lou"), ("露", "lou"), ("搂", "lou"),
            // lu
            ("路", "lu"), ("录", "lu"), ("陆", "lu"), ("露", "lu"), ("鲁", "lu"), ("炉", "lu"), ("鹿", "lu"),
            // lv
            ("旅", "lv"), ("绿", "lv"), ("律", "lv"), ("率", "lv"), ("虑", "lv"), ("驴", "lv"),
            // luan
            ("乱", "luan"), ("卵", "luan"),
            // lun
            ("论", "lun"), ("轮", "lun"), ("伦", "lun"),
            // luo
            ("落", "luo"), ("罗", "luo"), ("络", "luo"), ("洛", "luo"), ("萝", "luo"), ("螺", "luo"),
            // ma
            ("吗", "ma"), ("妈", "ma"), ("马", "ma"), ("麻", "ma"), ("骂", "ma"), ("码", "ma"), ("蚂", "ma"),
            // mai
            ("买", "mai"), ("卖", "mai"), ("麦", "mai"), ("埋", "mai"), ("迈", "mai"),
            // man
            ("满", "man"), ("慢", "man"), ("漫", "man"), ("蛮", "man"), ("瞒", "man"),
            // mang
            ("忙", "mang"), ("盲", "mang"), ("茫", "mang"), ("芒", "mang"),
            // mao
            ("毛", "mao"), ("猫", "mao"), ("冒", "mao"), ("帽", "mao"), ("贸", "mao"), ("矛", "mao"),
            // me
            ("么", "me"),
            // mei
            ("没", "mei"), ("每", "mei"), ("美", "mei"), ("妹", "mei"), ("媒", "mei"), ("梅", "mei"), ("霉", "mei"),
            // men
            ("门", "men"), ("们", "men"), ("闷", "men"),
            // meng
            ("梦", "meng"), ("猛", "meng"), ("蒙", "meng"), ("盟", "meng"), ("孟", "meng"),
            // mi
            ("米", "mi"), ("密", "mi"), ("迷", "mi"), ("秘", "mi"), ("蜜", "mi"), ("眯", "mi"),
            // mian
            ("面", "mian"), ("免", "mian"), ("棉", "mian"), ("眠", "mian"), ("绵", "mian"),
            // miao
            ("秒", "miao"), ("妙", "miao"), ("苗", "miao"), ("描", "miao"), ("庙", "miao"),
            // mie
            ("灭", "mie"),
            // min
            ("民", "min"), ("敏", "min"), ("闽", "min"),
            // ming
            ("明", "ming"), ("名", "ming"), ("命", "ming"), ("鸣", "ming"),
            // mo
            ("摸", "mo"), ("模", "mo"), ("末", "mo"), ("莫", "mo"), ("默", "mo"), ("墨", "mo"), ("磨", "mo"), ("魔", "mo"),
            // mou
            ("某", "mou"), ("谋", "mou"),
            // mu
            ("目", "mu"), ("木", "mu"), ("母", "mu"), ("亩", "mu"), ("牧", "mu"), ("墓", "mu"),
            // na
            ("那", "na"), ("拿", "na"), ("哪", "na"), ("纳", "na"),
            // nai
            ("奶", "nai"), ("耐", "nai"), ("乃", "nai"),
            // nan
            ("南", "nan"), ("男", "nan"), ("难", "nan"),
            // nang
            ("囊", "nang"),
            // nao
            ("脑", "nao"), ("闹", "nao"), ("恼", "nao"),
            // ne
            ("呢", "ne"),
            // nei
            ("内", "nei"),
            // nen
            ("嫩", "nen"),
            // neng
            ("能", "neng"),
            // ni
            ("你", "ni"), ("泥", "ni"), ("尼", "ni"), ("逆", "ni"),
            // nian
            ("年", "nian"), ("念", "nian"), ("粘", "nian"),
            // niang
            ("娘", "niang"), ("酿", "niang"),
            // niao
            ("鸟", "niao"), ("尿", "niao"),
            // nie
            ("捏", "nie"),
            // nin
            ("您", "nin"),
            // ning
            ("宁", "ning"), ("凝", "ning"),
            // niu
            ("牛", "niu"), ("扭", "niu"),
            // nong
            ("农", "nong"), ("弄", "nong"), ("浓", "nong"),
            // nu
            ("努", "nu"), ("怒", "nu"),
            // nv
            ("女", "nv"),
            // nuan
            ("暖", "nuan"),
            // ou
            ("偶", "ou"), ("欧", "ou"), ("殴", "ou"),
            // pa
            ("怕", "pa"), ("爬", "pa"), ("帕", "pa"),
            // pai
            ("排", "pai"), ("派", "pai"), ("牌", "pai"), ("拍", "pai"),
            // pan
            ("判", "pan"), ("盘", "pan"), ("盼", "pan"), ("叛", "pan"), ("攀", "pan"),
            // pang
            ("旁", "pang"), ("胖", "pang"),
            // pao
            ("跑", "pao"), ("炮", "pao"), ("泡", "pao"), ("抛", "pao"),
            // pei
            ("配", "pei"), ("培", "pei"), ("陪", "pei"), ("赔", "pei"), ("佩", "pei"),
            // pen
            ("盆", "pen"), ("喷", "pen"),
            // peng
            ("朋", "peng"), ("碰", "peng"), ("棚", "peng"), ("膨", "peng"),
            // pi
            ("批", "pi"), ("皮", "pi"), ("匹", "pi"), ("脾", "pi"), ("疲", "pi"), ("劈", "pi"),
            // pian
            ("片", "pian"), ("篇", "pian"), ("偏", "pian"), ("骗", "pian"),
            // piao
            ("票", "piao"), ("飘", "piao"), ("漂", "piao"),
            // pie
            ("撇", "pie"),
            // pin
            ("品", "pin"), ("拼", "pin"), ("贫", "pin"), ("频", "pin"),
            // ping
            ("平", "ping"), ("评", "ping"), ("瓶", "ping"), ("凭", "ping"), ("苹", "ping"),
            // po
            ("破", "po"), ("迫", "po"), ("坡", "po"), ("泼", "po"), ("婆", "po"),
            // pu
            ("普", "pu"), ("扑", "pu"), ("铺", "pu"), ("葡", "pu"), ("朴", "pu"),
            // qi
            ("起", "qi"), ("其", "qi"), ("七", "qi"), ("气", "qi"), ("期", "qi"), ("齐", "qi"), ("器", "qi"), ("奇", "qi"), ("企", "qi"), ("启", "qi"), ("汽", "qi"), ("妻", "qi"),
            // qia
            ("恰", "qia"), ("卡", "qia"),
            // qian
            ("前", "qian"), ("千", "qian"), ("钱", "qian"), ("签", "qian"), ("浅", "qian"), ("欠", "qian"), ("迁", "qian"), ("牵", "qian"), ("谦", "qian"),
            // qiang
            ("强", "qiang"), ("枪", "qiang"), ("墙", "qiang"), ("抢", "qiang"),
            // qiao
            ("桥", "qiao"), ("巧", "qiao"), ("敲", "qiao"), ("瞧", "qiao"), ("悄", "qiao"),
            // qie
            ("切", "qie"), ("且", "qie"),
            // qin
            ("亲", "qin"), ("琴", "qin"), ("勤", "qin"), ("侵", "qin"), ("秦", "qin"),
            // qing
            ("请", "qing"), ("青", "qing"), ("轻", "qing"), ("清", "qing"), ("情", "qing"), ("庆", "qing"), ("晴", "qing"), ("倾", "qing"),
            // qiong
            ("穷", "qiong"), ("琼", "qiong"),
            // qiu
            ("球", "qiu"), ("求", "qiu"), ("秋", "qiu"), ("丘", "qiu"),
            // qu
            ("去", "qu"), ("取", "qu"), ("区", "qu"), ("曲", "qu"), ("趣", "qu"), ("屈", "qu"), ("趋", "qu"),
            // quan
            ("全", "quan"), ("权", "quan"), ("劝", "quan"), ("圈", "quan"), ("拳", "quan"), ("泉", "quan"),
            // que
            ("却", "que"), ("确", "que"), ("缺", "que"), ("雀", "que"),
            // qun
            ("群", "qun"), ("裙", "qun"),
            // ran
            ("然", "ran"), ("染", "ran"), ("燃", "ran"),
            // rang
            ("让", "rang"), ("壤", "rang"),
            // rao
            ("绕", "rao"), ("扰", "rao"),
            // re
            ("热", "re"), ("惹", "re"),
            // ren
            ("人", "ren"), ("认", "ren"), ("任", "ren"), ("忍", "ren"), ("仁", "ren"),
            // reng
            ("仍", "reng"), ("扔", "reng"),
            // ri
            ("日", "ri"),
            // rong
            ("容", "rong"), ("荣", "rong"), ("融", "rong"), ("溶", "rong"), ("绒", "rong"),
            // rou
            ("肉", "rou"), ("柔", "rou"),
            // ru
            ("如", "ru"), ("入", "ru"), ("乳", "ru"), ("辱", "ru"),
            // ruan
            ("软", "ruan"),
            // rui
            ("瑞", "rui"), ("锐", "rui"),
            // run
            ("润", "run"), ("闰", "run"),
            // ruo
            ("若", "ruo"), ("弱", "ruo"),
            // sa
            ("洒", "sa"), ("撒", "sa"),
            // sai
            ("赛", "sai"), ("塞", "sai"), ("腮", "sai"),
            // san
            ("三", "san"), ("散", "san"), ("伞", "san"),
            // sang
            ("丧", "sang"), ("桑", "sang"), ("嗓", "sang"),
            // sao
            ("扫", "sao"), ("嫂", "sao"),
            // se
            ("色", "se"), ("塞", "se"),
            // sen
            ("森", "sen"),
            // sha
            ("杀", "sha"), ("沙", "sha"), ("傻", "sha"), ("纱", "sha"), ("砂", "sha"),
            // shai
            ("晒", "shai"), ("筛", "shai"),
            // shan
            ("山", "shan"), ("闪", "shan"), ("善", "shan"), ("扇", "shan"), ("衫", "shan"),
            // shang
            ("上", "shang"), ("商", "shang"), ("伤", "shang"), ("赏", "shang"), ("尚", "shang"),
            // shao
            ("少", "shao"), ("烧", "shao"), ("稍", "shao"), ("绍", "shao"), ("勺", "shao"),
            // she
            ("社", "she"), ("设", "she"), ("射", "she"), ("蛇", "she"), ("舍", "she"), ("涉", "she"),
            // shei
            ("谁", "shei"),
            // shen
            ("身", "shen"), ("深", "shen"), ("神", "shen"), ("什", "shen"), ("甚", "shen"), ("审", "shen"), ("伸", "shen"),
            // sheng
            ("生", "sheng"), ("声", "sheng"), ("省", "sheng"), ("胜", "sheng"), ("升", "sheng"), ("圣", "sheng"), ("剩", "sheng"),
            // shi
            ("是", "shi"), ("时", "shi"), ("十", "shi"), ("事", "shi"), ("实", "shi"), ("使", "shi"), ("世", "shi"), ("市", "shi"), ("式", "shi"), ("识", "shi"), ("始", "shi"), ("师", "shi"), ("士", "shi"), ("石", "shi"), ("示", "shi"), ("史", "shi"), ("失", "shi"), ("施", "shi"), ("食", "shi"), ("试", "shi"),
            // shou
            ("手", "shou"), ("受", "shou"), ("首", "shou"), ("收", "shou"), ("守", "shou"), ("售", "shou"), ("瘦", "shou"),
            // shu
            ("书", "shu"), ("数", "shu"), ("树", "shu"), ("术", "shu"), ("属", "shu"), ("输", "shu"), ("述", "shu"), ("熟", "shu"), ("束", "shu"), ("鼠", "shu"),
            // shua
            ("刷", "shua"), ("耍", "shua"),
            // shuai
            ("摔", "shuai"), ("帅", "shuai"), ("衰", "shuai"),
            // shuan
            ("栓", "shuan"),
            // shuang
            ("双", "shuang"), ("爽", "shuang"), ("霜", "shuang"),
            // shui
            ("水", "shui"), ("睡", "shui"), ("税", "shui"),
            // shun
            ("顺", "shun"), ("瞬", "shun"),
            // shuo
            ("说", "shuo"),
            // si
            ("四", "si"), ("死", "si"), ("丝", "si"), ("思", "si"), ("私", "si"), ("司", "si"), ("似", "si"), ("撕", "si"),
            // song
            ("送", "song"), ("松", "song"), ("宋", "song"), ("颂", "song"),
            // sou
            ("搜", "sou"), ("艘", "sou"),
            // su
            ("速", "su"), ("苏", "su"), ("素", "su"), ("诉", "su"), ("塑", "su"), ("宿", "su"), ("肃", "su"),
            // suan
            ("算", "suan"), ("酸", "suan"),
            // sui
            ("岁", "sui"), ("随", "sui"), ("虽", "sui"), ("碎", "sui"),
            // sun
            ("孙", "sun"), ("损", "sun"),
            // suo
            ("所", "suo"), ("缩", "suo"), ("索", "suo"), ("锁", "suo"),
            // ta
            ("他", "ta"), ("她", "ta"), ("它", "ta"), ("塔", "ta"), ("踏", "ta"),
            // tai
            ("太", "tai"), ("台", "tai"), ("态", "tai"), ("抬", "tai"), ("泰", "tai"),
            // tan
            ("谈", "tan"), ("弹", "tan"), ("探", "tan"), ("坦", "tan"), ("炭", "tan"), ("叹", "tan"),
            // tang
            ("堂", "tang"), ("糖", "tang"), ("唐", "tang"), ("躺", "tang"), ("汤", "tang"), ("趟", "tang"),
            // tao
            ("逃", "tao"), ("套", "tao"), ("桃", "tao"), ("讨", "tao"), ("掏", "tao"), ("陶", "tao"),
            // te
            ("特", "te"),
            // teng
            ("疼", "teng"), ("腾", "teng"), ("藤", "teng"),
            // ti
            ("题", "ti"), ("提", "ti"), ("体", "ti"), ("替", "ti"), ("踢", "ti"), ("梯", "ti"),
            // tian
            ("天", "tian"), ("田", "tian"), ("填", "tian"), ("甜", "tian"),
            // tiao
            ("条", "tiao"), ("调", "tiao"), ("跳", "tiao"), ("挑", "tiao"),
            // tie
            ("铁", "tie"), ("贴", "tie"),
            // ting
            ("听", "ting"), ("停", "ting"), ("庭", "ting"), ("厅", "ting"), ("挺", "ting"),
            // tong
            ("同", "tong"), ("通", "tong"), ("统", "tong"), ("痛", "tong"), ("铜", "tong"), ("童", "tong"),
            // tou
            ("头", "tou"), ("投", "tou"), ("透", "tou"), ("偷", "tou"),
            // tu
            ("图", "tu"), ("土", "tu"), ("突", "tu"), ("途", "tu"), ("涂", "tu"), ("兔", "tu"),
            // tuan
            ("团", "tuan"),
            // tui
            ("推", "tui"), ("退", "tui"), ("腿", "tui"),
            // tun
            ("吞", "tun"),
            // tuo
            ("脱", "tuo"), ("托", "tuo"), ("拖", "tuo"), ("妥", "tuo"),
            // wa
            ("瓦", "wa"), ("挖", "wa"), ("蛙", "wa"), ("娃", "wa"),
            // wai
            ("外", "wai"), ("歪", "wai"),
            // wan
            ("完", "wan"), ("万", "wan"), ("晚", "wan"), ("玩", "wan"), ("碗", "wan"), ("湾", "wan"), ("挽", "wan"),
            // wang
            ("往", "wang"), ("王", "wang"), ("望", "wang"), ("网", "wang"), ("忘", "wang"), ("亡", "wang"), ("旺", "wang"),
            // wei
            ("为", "wei"), ("位", "wei"), ("未", "wei"), ("委", "wei"), ("微", "wei"), ("围", "wei"), ("维", "wei"), ("味", "wei"), ("卫", "wei"), ("威", "wei"), ("伟", "wei"), ("唯", "wei"), ("危", "wei"),
            // wen
            ("问", "wen"), ("文", "wen"), ("温", "wen"), ("闻", "wen"), ("稳", "wen"), ("纹", "wen"),
            // weng
            ("翁", "weng"),
            // wo
            ("我", "wo"), ("握", "wo"), ("窝", "wo"),
            // wu
            ("无", "wu"), ("五", "wu"), ("物", "wu"), ("务", "wu"), ("午", "wu"), ("舞", "wu"), ("武", "wu"), ("误", "wu"), ("雾", "wu"), ("屋", "wu"), ("乌", "wu"), ("污", "wu"),
            // xi
            ("西", "xi"), ("系", "xi"), ("细", "xi"), ("希", "xi"), ("息", "xi"), ("喜", "xi"), ("吸", "xi"), ("习", "xi"), ("席", "xi"), ("戏", "xi"), ("洗", "xi"), ("析", "xi"),
            // xia
            ("下", "xia"), ("夏", "xia"), ("吓", "xia"), ("峡", "xia"), ("狭", "xia"), ("虾", "xia"),
            // xian
            ("先", "xian"), ("现", "xian"), ("线", "xian"), ("显", "xian"), ("险", "xian"), ("县", "xian"), ("献", "xian"), ("限", "xian"), ("鲜", "xian"), ("闲", "xian"), ("贤", "xian"),
            // xiang
            ("想", "xiang"), ("向", "xiang"), ("象", "xiang"), ("相", "xiang"), ("香", "xiang"), ("乡", "xiang"), ("响", "xiang"), ("箱", "xiang"), ("详", "xiang"), ("享", "xiang"),
            // xiao
            ("小", "xiao"), ("笑", "xiao"), ("校", "xiao"), ("消", "xiao"), ("效", "xiao"), ("晓", "xiao"), ("销", "xiao"), ("萧", "xiao"),
            // xie
            ("写", "xie"), ("些", "xie"), ("谢", "xie"), ("协", "xie"), ("血", "xie"), ("鞋", "xie"), ("械", "xie"), ("泄", "xie"),
            // xin
            ("新", "xin"), ("心", "xin"), ("信", "xin"), ("辛", "xin"), ("欣", "xin"),
            // xing
            ("行", "xing"), ("性", "xing"), ("星", "xing"), ("形", "xing"), ("兴", "xing"), ("醒", "xing"), ("姓", "xing"), ("幸", "xing"),
            // xiong
            ("兄", "xiong"), ("雄", "xiong"), ("胸", "xiong"), ("凶", "xiong"),
            // xiu
            ("修", "xiu"), ("秀", "xiu"), ("休", "xiu"), ("袖", "xiu"), ("锈", "xiu"),
            // xu
            ("需", "xu"), ("许", "xu"), ("续", "xu"), ("须", "xu"), ("序", "xu"), ("虚", "xu"), ("徐", "xu"),
            // xuan
            ("选", "xuan"), ("宣", "xuan"), ("旋", "xuan"), ("悬", "xuan"), ("玄", "xuan"),
            // xue
            ("学", "xue"), ("血", "xue"), ("雪", "xue"), ("穴", "xue"),
            // xun
            ("寻", "xun"), ("训", "xun"), ("迅", "xun"), ("讯", "xun"), ("巡", "xun"), ("循", "xun"),
            // ya
            ("压", "ya"), ("呀", "ya"), ("牙", "ya"), ("亚", "ya"), ("芽", "ya"), ("鸦", "ya"), ("鸭", "ya"),
            // yan
            ("眼", "yan"), ("言", "yan"), ("烟", "yan"), ("研", "yan"), ("演", "yan"), ("严", "yan"), ("沿", "yan"), ("盐", "yan"), ("颜", "yan"), ("延", "yan"), ("验", "yan"), ("岩", "yan"),
            // yang
            ("样", "yang"), ("阳", "yang"), ("养", "yang"), ("洋", "yang"), ("扬", "yang"), ("羊", "yang"), ("央", "yang"),
            // yao
            ("要", "yao"), ("药", "yao"), ("摇", "yao"), ("咬", "yao"), ("腰", "yao"), ("遥", "yao"), ("邀", "yao"),
            // ye
            ("也", "ye"), ("业", "ye"), ("夜", "ye"), ("叶", "ye"), ("野", "ye"), ("爷", "ye"), ("液", "ye"), ("页", "ye"),
            // yi
            ("一", "yi"), ("以", "yi"), ("已", "yi"), ("意", "yi"), ("义", "yi"), ("议", "yi"), ("易", "yi"), ("医", "yi"), ("衣", "yi"), ("依", "yi"), ("艺", "yi"), ("移", "yi"), ("益", "yi"), ("异", "yi"), ("疑", "yi"), ("宜", "yi"),
            // yin
            ("因", "yin"), ("引", "yin"), ("银", "yin"), ("印", "yin"), ("音", "yin"), ("饮", "yin"), ("隐", "yin"), ("阴", "yin"),
            // ying
            ("应", "ying"), ("英", "ying"), ("影", "ying"), ("营", "ying"), ("迎", "ying"), ("映", "ying"), ("硬", "ying"), ("赢", "ying"),
            // yo
            ("哟", "yo"),
            // yong
            ("用", "yong"), ("永", "yong"), ("勇", "yong"), ("拥", "yong"), ("泳", "yong"), ("涌", "yong"),
            // you
            ("有", "you"), ("又", "you"), ("右", "you"), ("由", "you"), ("油", "you"), ("游", "you"), ("优", "you"), ("友", "you"), ("尤", "you"), ("邮", "you"), ("犹", "you"),
            // yu
            ("与", "yu"), ("于", "yu"), ("语", "yu"), ("雨", "yu"), ("玉", "yu"), ("鱼", "yu"), ("预", "yu"), ("遇", "yu"), ("余", "yu"), ("域", "yu"), ("育", "yu"), ("欲", "yu"), ("愈", "yu"), ("狱", "yu"),
            // yuan
            ("员", "yuan"), ("原", "yuan"), ("远", "yuan"), ("院", "yuan"), ("圆", "yuan"), ("愿", "yuan"), ("源", "yuan"), ("元", "yuan"), ("园", "yuan"), ("援", "yuan"),
            // yue
            ("月", "yue"), ("越", "yue"), ("约", "yue"), ("阅", "yue"), ("乐", "yue"), ("跃", "yue"),
            // yun
            ("运", "yun"), ("云", "yun"), ("允", "yun"), ("韵", "yun"), ("孕", "yun"),
            // za
            ("杂", "za"), ("砸", "za"),
            // zai
            ("在", "zai"), ("再", "zai"), ("载", "zai"), ("灾", "zai"), ("栽", "zai"),
            // zan
            ("赞", "zan"), ("咱", "zan"), ("暂", "zan"),
            // zang
            ("脏", "zang"), ("葬", "zang"),
            // zao
            ("早", "zao"), ("造", "zao"), ("遭", "zao"), ("糟", "zao"), ("枣", "zao"), ("燥", "zao"),
            // ze
            ("则", "ze"), ("责", "ze"), ("择", "ze"),
            // zei
            ("贼", "zei"),
            // zen
            ("怎", "zen"),
            // zeng
            ("增", "zeng"), ("赠", "zeng"),
            // zha
            ("扎", "zha"), ("炸", "zha"), ("闸", "zha"), ("渣", "zha"),
            // zhai
            ("摘", "zhai"), ("宅", "zhai"), ("窄", "zhai"), ("债", "zhai"),
            // zhan
            ("站", "zhan"), ("战", "zhan"), ("展", "zhan"), ("占", "zhan"), ("粘", "zhan"), ("斩", "zhan"),
            // zhang
            ("张", "zhang"), ("长", "zhang"), ("章", "zhang"), ("掌", "zhang"), ("丈", "zhang"), ("障", "zhang"),
            // zhao
            ("找", "zhao"), ("照", "zhao"), ("招", "zhao"), ("赵", "zhao"), ("召", "zhao"), ("罩", "zhao"),
            // zhe
            ("这", "zhe"), ("者", "zhe"), ("折", "zhe"), ("哲", "zhe"), ("遮", "zhe"),
            // zhen
            ("真", "zhen"), ("阵", "zhen"), ("镇", "zhen"), ("针", "zhen"), ("诊", "zhen"), ("震", "zhen"), ("振", "zhen"),
            // zheng
            ("正", "zheng"), ("政", "zheng"), ("整", "zheng"), ("证", "zheng"), ("争", "zheng"), ("征", "zheng"), ("睁", "zheng"),
            // zhi
            ("只", "zhi"), ("之", "zhi"), ("知", "zhi"), ("制", "zhi"), ("指", "zhi"), ("直", "zhi"), ("治", "zhi"), ("志", "zhi"), ("支", "zhi"), ("至", "zhi"), ("值", "zhi"), ("职", "zhi"), ("止", "zhi"), ("纸", "zhi"), ("质", "zhi"), ("置", "zhi"),
            // zhong
            ("中", "zhong"), ("重", "zhong"), ("种", "zhong"), ("众", "zhong"), ("终", "zhong"), ("钟", "zhong"),
            // zhou
            ("周", "zhou"), ("州", "zhou"), ("洲", "zhou"), ("轴", "zhou"), ("粥", "zhou"),
            // zhu
            ("主", "zhu"), ("住", "zhu"), ("注", "zhu"), ("助", "zhu"), ("著", "zhu"), ("逐", "zhu"), ("筑", "zhu"), ("祝", "zhu"), ("朱", "zhu"), ("猪", "zhu"), ("珠", "zhu"), ("竹", "zhu"),
            // zhua
            ("抓", "zhua"),
            // zhuai
            ("拽", "zhuai"),
            // zhuan
            ("转", "zhuan"), ("专", "zhuan"), ("赚", "zhuan"),
            // zhuang
            ("装", "zhuang"), ("状", "zhuang"), ("庄", "zhuang"), ("撞", "zhuang"), ("壮", "zhuang"),
            // zhui
            ("追", "zhui"), ("坠", "zhui"),
            // zhun
            ("准", "zhun"),
            // zhuo
            ("桌", "zhuo"), ("捉", "zhuo"), ("卓", "zhuo"), ("浊", "zhuo"),
            // zi
            ("子", "zi"), ("自", "zi"), ("字", "zi"), ("资", "zi"), ("紫", "zi"), ("姿", "zi"), ("滋", "zi"),
            // zong
            ("总", "zong"), ("纵", "zong"), ("宗", "zong"), ("踪", "zong"),
            // zou
            ("走", "zou"), ("奏", "zou"),
            // zu
            ("组", "zu"), ("族", "zu"), ("足", "zu"), ("祖", "zu"), ("阻", "zu"),
            // zuan
            ("钻", "zuan"),
            // zui
            ("最", "zui"), ("嘴", "zui"), ("醉", "zui"), ("罪", "zui"),
            // zun
            ("尊", "zun"), ("遵", "zun"),
            // zuo
            ("做", "zuo"), ("作", "zuo"), ("坐", "zuo"), ("座", "zuo"), ("左", "zuo"),
        ]

        for (char, py) in charPinyinPairs {
            if pinyinToChars[py] == nil {
                pinyinToChars[py] = [char]
            } else {
                pinyinToChars[py]?.append(char)
            }
        }
    }

    // MARK: - Persistence

    private func saveCache() {
        let data: [String: Any] = [
            "wrongAnswers": wrongAnswers,
            "lastSyncTimestamp": lastSyncTimestamp ?? Date.distantPast,
            "processedSessionIDs": Array(processedSessionIDs)
        ]
        do {
            let archived = NSKeyedArchiver.archivedData(withRootObject: data)
            try archived.write(to: cacheURL, options: .atomicWrite)
        } catch {
            print("[WrongAnswerBookManager] Failed to save cache: \(error)")
        }
    }

    private func loadCache() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }
        do {
            let data = try Data(contentsOf: cacheURL)
            if let dict = NSKeyedUnarchiver.unarchiveObject(with: data) as? [String: Any] {
                self.wrongAnswers = dict["wrongAnswers"] as? [WrongAnswerItem] ?? []
                self.lastSyncTimestamp = dict["lastSyncTimestamp"] as? Date ?? Date.distantPast
                self.processedSessionIDs = Set(dict["processedSessionIDs"] as? [String] ?? [])
            }
        } catch {
            print("[WrongAnswerBookManager] Failed to load cache: \(error)")
        }
    }

    private func saveQuizProgress() {
        do {
            let data = NSKeyedArchiver.archivedData(withRootObject: quizProgress)
            try data.write(to: quizProgressURL, options: .atomicWrite)
        } catch {
            print("[WrongAnswerBookManager] Failed to save quiz progress: \(error)")
        }
    }

    private func loadQuizProgress() {
        guard FileManager.default.fileExists(atPath: quizProgressURL.path) else { return }
        do {
            let data = try Data(contentsOf: quizProgressURL)
            if let progress = NSKeyedUnarchiver.unarchiveObject(with: data) as? QuizProgress {
                self.quizProgress = progress
            }
        } catch {
            print("[WrongAnswerBookManager] Failed to load quiz progress: \(error)")
        }
    }

    /// Clears all cached wrong answers (for debugging).
    func clearAllData() {
        wrongAnswers = []
        processedSessionIDs = []
        lastSyncTimestamp = nil
        quizProgress = QuizProgress()
        saveCache()
        saveQuizProgress()
    }
}
