import UIKit
import AVFoundation

// MARK: - Reading View Controller
/// Manages the reading session: shows expected text, records audio,
/// performs speech-to-text, and supports pause/resume/stop.
final class ReadingViewController: UIViewController {

    // MARK: - Properties
    private let taskId: String
    private var task: ReadingTask? {
        return TaskManager.shared.task(withId: taskId)
    }

    // Pluggable services
    private let speechService: SpeechRecognitionServiceProtocol = AppleSpeechRecognitionService()
    private let scoringService: ScoringServiceProtocol = DiffScoringService()
    private let audioRecordingManager = AudioRecordingManager.shared

    // State
    private var currentTextIndex = 0
    private var isRecording = false
    private var currentSession: ReadingSession?

    // Timer for duration display
    private var timer: Timer?
    private var elapsedSeconds: Int = 0
    
    // Auto-next-paragraph mode
    private var isAutoNextEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "auto_next_paragraph_enabled")
    }
    /// Threshold: minimum score (0-100) required to auto-advance. Configurable in Settings.
    private var autoNextScoreThreshold: Double {
        return userDefaultsDouble(forKey: "auto_next_score_threshold", defaultValue: 50.0)
    }
    /// Delay in seconds before auto-advancing after a good match. Configurable in Settings.
    private var autoNextDelay: TimeInterval {
        return userDefaultsDouble(forKey: "auto_next_delay", defaultValue: 1.5)
    }
    /// Pending auto-advance work item (cancellable).
    private var autoNextWorkItem: DispatchWorkItem?
    
    // Silence detection for auto-next (since SFSpeechRecognizer.isFinal rarely fires during live recording)
    /// Timestamp of the last partial result received.
    private var lastPartialResultTime: Date = Date()
    /// The latest partial result text.
    private var lastPartialResultText: String = ""
    /// Timer that periodically checks if the user has stopped speaking.
    private var silenceDetectionTimer: Timer?
    /// Silence duration required before considering the user has finished speaking. Configurable in Settings.
    private var silenceThreshold: TimeInterval {
        return userDefaultsDouble(forKey: "auto_next_silence_threshold", defaultValue: 2.0)
    }
    /// Prevents double-triggering auto-advance for the same paragraph.
    private var hasAutoAdvancedForCurrentText: Bool = false
    
    /// Helper: reads a UserDefaults double, returning defaultValue if never set.
    private func userDefaultsDouble(forKey key: String, defaultValue: Double) -> Double {
        guard UserDefaults.standard.object(forKey: key) != nil else { return defaultValue }
        return UserDefaults.standard.double(forKey: key)
    }

    // MARK: - Subviews
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let progressView = ReadingProgressView()
    private let expectedTextLabel = UILabel()
    private let recognizedTextLabel = UILabel()
    private let statusLabel = UILabel()
    private let autoNextIndicator = UILabel()
    private let timerLabel = UILabel()
    private let recordButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let finishButton = UIButton(type: .system)

    // MARK: - Initialization
    init(taskId: String) {
        self.taskId = taskId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSpeechService()
        updateContentForCurrentIndex()
        setupNavigationBar()
    }

    private func setupNavigationBar() {
        let editButton = UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(editExpectedTextTapped))
        navigationItem.rightBarButtonItem = editButton
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isRecording {
            stopRecording()
        }
        // Ensure audio recording manager is fully stopped
        if audioRecordingManager.isRecording {
            audioRecordingManager.stopRecording(keepFile: false)
        }
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "阅读中"

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Content Stack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        // Progress
        progressView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(progressView)
        progressView.heightAnchor.constraint(equalToConstant: 20).isActive = true

        // Expected Text Section
        let expectedTitleLabel = UILabel()
        expectedTitleLabel.text = "📖 期望文本"
        expectedTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        expectedTitleLabel.textColor = .textSecondary
        contentStack.addArrangedSubview(expectedTitleLabel)

        expectedTextLabel.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        expectedTextLabel.textColor = .textPrimary
        expectedTextLabel.numberOfLines = 0
        expectedTextLabel.textAlignment = .center
        contentStack.addArrangedSubview(expectedTextLabel)

        // Separator
        let separator1 = createSeparator()
        contentStack.addArrangedSubview(separator1)

        // Recognized Text Section
        let recognizedTitleLabel = UILabel()
        recognizedTitleLabel.text = "🎙 识别文本"
        recognizedTitleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        recognizedTitleLabel.textColor = .textSecondary
        contentStack.addArrangedSubview(recognizedTitleLabel)

        recognizedTextLabel.font = UIFont.systemFont(ofSize: 16)
        recognizedTextLabel.textColor = .primary
        recognizedTextLabel.numberOfLines = 0
        recognizedTextLabel.text = "等待录音..."
        contentStack.addArrangedSubview(recognizedTextLabel)

        // Timer
        timerLabel.font = UIFont.systemFont(ofSize: 36, weight: .light)
        timerLabel.textColor = .textPrimary
        timerLabel.textAlignment = .center
        timerLabel.text = "00:00"
        contentStack.addArrangedSubview(timerLabel)

        // Status
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.textColor = .textSecondary
        statusLabel.textAlignment = .center
        statusLabel.text = "准备就绪"
        contentStack.addArrangedSubview(statusLabel)
        
        // Auto-next indicator
        autoNextIndicator.font = UIFont.systemFont(ofSize: 12)
        autoNextIndicator.textColor = .primary
        autoNextIndicator.textAlignment = .center
        autoNextIndicator.text = isAutoNextEnabled ? "⏭ 自动下一段已开启" : ""
        contentStack.addArrangedSubview(autoNextIndicator)

        // Separator
        let separator2 = createSeparator()
        contentStack.addArrangedSubview(separator2)

        // Buttons
        let buttonStack = UIStackView()
        buttonStack.axis = .vertical
        buttonStack.spacing = 10

        // Record / Stop button
        recordButton.setTitle("🎤 开始录音", for: .normal)
        recordButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        recordButton.setTitleColor(.white, for: .normal)
        recordButton.backgroundColor = .errorRed
        recordButton.layer.cornerRadius = 12
        recordButton.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        buttonStack.addArrangedSubview(recordButton)
        recordButton.heightAnchor.constraint(equalToConstant: 50).isActive = true

        // Pause / Resume button
        pauseButton.setTitle("⏸ 暂停", for: .normal)
        pauseButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        pauseButton.setTitleColor(.white, for: .normal)
        pauseButton.backgroundColor = .warningOrange
        pauseButton.layer.cornerRadius = 10
        pauseButton.isEnabled = false
        pauseButton.alpha = 0.5
        pauseButton.addTarget(self, action: #selector(pauseButtonTapped), for: .touchUpInside)
        buttonStack.addArrangedSubview(pauseButton)
        pauseButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Next text button
        nextButton.setTitle("下一段 →", for: .normal)
        nextButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.backgroundColor = .primary
        nextButton.layer.cornerRadius = 10
        nextButton.addTarget(self, action: #selector(nextButtonTapped), for: .touchUpInside)
        nextButton.isEnabled = false
        nextButton.alpha = 0.5
        buttonStack.addArrangedSubview(nextButton)
        nextButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Finish all
        finishButton.setTitle("✅ 完成全部", for: .normal)
        finishButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        finishButton.setTitleColor(.white, for: .normal)
        finishButton.backgroundColor = .successGreen
        finishButton.layer.cornerRadius = 10
        finishButton.addTarget(self, action: #selector(finishButtonTapped), for: .touchUpInside)
        buttonStack.addArrangedSubview(finishButton)
        finishButton.heightAnchor.constraint(equalToConstant: 44).isActive = true

        contentStack.addArrangedSubview(buttonStack)

        // Layout
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            scrollView.bottomAnchor.constraint(equalTo: compatSafeAreaBottom),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40)
        ])

        updateProgressView()
    }

    private func createSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return view
    }

    private func setupSpeechService() {
        speechService.delegate = self
    }

    // MARK: - Content Updates

    private func updateContentForCurrentIndex() {
        guard let task = task else { return }

        if currentTextIndex < task.expectedTexts.count {
            expectedTextLabel.text = task.expectedTexts[currentTextIndex]
            recognizedTextLabel.text = "等待录音..."
            statusLabel.text = "准备就绪 - 第 \(currentTextIndex + 1)/\(task.expectedTexts.count) 段"
            nextButton.isEnabled = false
            nextButton.alpha = 0.5
            autoNextIndicator.text = isAutoNextEnabled ? "⏭ 自动下一段已开启" : ""
            // Reset auto-advance state for new paragraph
            hasAutoAdvancedForCurrentText = false
            lastPartialResultTime = Date()
            lastPartialResultText = ""
        } else {
            expectedTextLabel.text = "全部完成！"
            recognizedTextLabel.text = ""
            statusLabel.text = "所有文本已阅读完毕"
            autoNextIndicator.text = ""
        }

        updateProgressView()
    }

    private func updateProgressView() {
        guard let task = task else { return }
        let readIndices = Set(task.sessions.map { $0.expectedTextIndex })
        progressView.configure(total: task.expectedTexts.count, completedIndices: readIndices, currentIndex: currentTextIndex)
    }

    // MARK: - Timer
    private func startTimer() {
        elapsedSeconds = 0
        timerLabel.text = "00:00"
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsedSeconds += 1
            let minutes = self.elapsedSeconds / 60
            let seconds = self.elapsedSeconds % 60
            self.timerLabel.text = String(format: "%02d:%02d", minutes, seconds)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Actions

    @objc private func recordButtonTapped() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        AudioSessionManager.shared.requestRecordingPermission { [weak self] granted in
            guard let self = self else { return }
            if granted {
                do {
                    // Cancel any pending auto-advance since user is manually starting
                    self.cancelAutoNext()
                    self.autoNextIndicator.text = self.isAutoNextEnabled ? "⏭ 自动下一段已开启" : ""
                    self.autoNextIndicator.textColor = .primary
                    
                    // Delete old audio file if re-recording
                    if let oldPath = self.currentSession?.audioFilePath {
                        AudioRecordingManager.deleteAudioFile(at: oldPath)
                    }

                    // Start audio file recording first (before speech recognition,
                    // since speech recognition also needs the audio session)
                    let audioFilePath = try self.audioRecordingManager.startRecording()

                    // Create a new session with the audio file path
                    self.currentSession = ReadingSession(
                        expectedTextIndex: self.currentTextIndex,
                        audioFilePath: audioFilePath
                    )

                    // Provide expected text as context to improve recognition accuracy
                    let expectedText = self.task?.expectedTexts[self.currentTextIndex] ?? ""
                    let contextualStrings = Self.extractContextualStrings(from: expectedText)
                    try self.speechService.startRecognition(locale: Locale(identifier: "zh-CN"), contextualStrings: contextualStrings)
                    self.isRecording = true
                    self.startTimer()
                    
                    // Silence detection: only active when auto-next mode is ON.
                    // When OFF, the user manually stops recording (→ endAudio()).
                    self.lastPartialResultTime = Date()
                    self.lastPartialResultText = ""
                    self.hasAutoAdvancedForCurrentText = false
                    if self.isAutoNextEnabled {
                        self.startSilenceDetection()
                    }

                    self.recordButton.setTitle("⏹ 停止录音", for: .normal)
                    self.recordButton.backgroundColor = .textSecondary
                    self.pauseButton.isEnabled = true
                    self.pauseButton.alpha = 1.0
                    self.statusLabel.text = "正在录音..."
                    self.statusLabel.textColor = .errorRed
                } catch {
                    self.showAlert(title: "录音失败", message: error.localizedDescription)
                }
            } else {
                self.showAlert(title: "权限不足", message: "请在系统设置中开启麦克风权限")
            }
        }
    }

    private func stopRecording() {
        // Cancel any pending auto-advance (no-op when auto-next is OFF)
        cancelAutoNext()
        stopSilenceDetection()
        
        // Always call stopRecognition() → endAudio() so the recognizer can
        // produce a final result. This is the normal path for manual-stop mode.
        speechService.stopRecognition()
        audioRecordingManager.stopRecording(keepFile: true)
        isRecording = false
        stopTimer()

        recordButton.setTitle("🎤 重新录音", for: .normal)
        recordButton.backgroundColor = .errorRed
        pauseButton.isEnabled = false
        pauseButton.alpha = 0.5
        pauseButton.setTitle("⏸ 暂停", for: .normal)
        statusLabel.text = "录音已停止"
        statusLabel.textColor = .textSecondary

        // Enable next if we have recognized text
        let hasText = !recognizedTextLabel.text!.isEmpty && recognizedTextLabel.text != "等待录音..."
        nextButton.isEnabled = hasText
        nextButton.alpha = hasText ? 1.0 : 0.5
        
        // Reset auto-next indicator
        autoNextIndicator.text = isAutoNextEnabled ? "⏭ 自动下一段已开启" : ""
        autoNextIndicator.textColor = .primary
    }

    @objc private func pauseButtonTapped() {
        if speechService.isRecognizing {
            speechService.pauseRecognition()
            audioRecordingManager.pauseRecording()
            pauseButton.setTitle("▶ 继续", for: .normal)
            statusLabel.text = "已暂停"
            statusLabel.textColor = .warningOrange
            stopTimer()
            stopSilenceDetection()
        } else {
            do {
                try speechService.resumeRecognition()
                audioRecordingManager.resumeRecording()
                pauseButton.setTitle("⏸ 暂停", for: .normal)
                statusLabel.text = "正在录音..."
                statusLabel.textColor = .errorRed
                startTimer()
                // Reset silence detection on resume (only if auto-next is ON)
                lastPartialResultTime = Date()
                lastPartialResultText = ""
                if isAutoNextEnabled {
                    startSilenceDetection()
                }
            } catch {
                showAlert(title: "恢复失败", message: error.localizedDescription)
            }
        }
    }

    @objc private func nextButtonTapped() {
        guard let task = task else { return }
        
        // Cancel any pending auto-advance
        cancelAutoNext()

        // Score current session
        if let session = currentSession {
            let expected = task.expectedTexts[currentTextIndex]
            let actual = recognizedTextLabel.text ?? ""
            let result = scoringService.compare(expected: expected, actual: actual)
            session.result = result
            session.recognizedText = actual
            session.endTime = Date()
            TaskManager.shared.addSession(session, toTaskId: task.id)
        }

        // Move to next text
        currentTextIndex += 1
        currentSession = nil

        if currentTextIndex >= task.expectedTexts.count {
            // All done - show aggregate score with option to re-read
            showAggregateResults()
        } else {
            updateContentForCurrentIndex()
            // Scroll to top
            scrollView.setContentOffset(.zero, animated: true)
        }
    }

    @objc private func finishButtonTapped() {
        guard let task = task else { return }

        showConfirm(title: "完成全部", message: "确定要结束所有阅读吗？") { [weak self] in
            guard let self = self else { return }

            // Stop recording if active
            if self.isRecording {
                self.stopRecording()
            }

            // Score current session if any
            if let session = self.currentSession, self.currentTextIndex < task.expectedTexts.count {
                let expected = task.expectedTexts[self.currentTextIndex]
                let actual = self.recognizedTextLabel.text ?? ""
                let result = self.scoringService.compare(expected: expected, actual: actual)
                session.result = result
                session.recognizedText = actual
                session.endTime = Date()
                TaskManager.shared.addSession(session, toTaskId: task.id)
            }

            self.showAggregateResults()
        }
    }

    private func showAggregateResults() {
        guard let task = task else { return }

        // Aggregate all session scores
        let results = task.sessions.compactMap { $0.result }
        let overallScore = scoringService.aggregateScore(from: results)

        let message = results.isEmpty
            ? "暂无评分数据"
            : "总体得分：\(Int(overallScore))%\n共完成 \(results.count) 段文本的阅读"

        let alert = UIAlertController(title: "阅读完成", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重新阅读", style: .default) { [weak self] _ in
            guard let self = self else { return }
            // Clean up any dangling audio before resetting
            if self.audioRecordingManager.isRecording {
                self.audioRecordingManager.stopRecording(keepFile: false)
            }
            self.currentTextIndex = 0
            self.currentSession = nil
            self.updateContentForCurrentIndex()
            // Reset buttons
            self.recordButton.setTitle("🎤 开始录音", for: .normal)
            self.recordButton.backgroundColor = .errorRed
            self.pauseButton.isEnabled = false
            self.pauseButton.alpha = 0.5
            self.pauseButton.setTitle("⏸ 暂停", for: .normal)
            self.nextButton.isEnabled = false
            self.nextButton.alpha = 0.5
            self.timerLabel.text = "00:00"
            self.elapsedSeconds = 0
            self.statusLabel.text = "准备就绪"
            self.statusLabel.textColor = .textSecondary
            self.scrollView.setContentOffset(.zero, animated: true)
        })
        alert.addAction(UIAlertAction(title: "返回", style: .cancel) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func editExpectedTextTapped() {
        guard let task = task, currentTextIndex < task.expectedTexts.count else { return }

        let inputVC = TextInputViewController(initialText: task.expectedTexts[currentTextIndex])
        inputVC.onSave = { [weak self] newText in
            guard let self = self, let task = self.task else { return }
            task.expectedTexts[self.currentTextIndex] = newText
            TaskManager.shared.updateTask(task)
            self.expectedTextLabel.text = newText
        }
        let nav = UINavigationController(rootViewController: inputVC)
        present(nav, animated: true)
    }

    // MARK: - Context Extraction Helper

    /// Extracts contextual strings from expected text to bias speech recognition.
    ///
    /// Uses word-level granularity so the recognizer gets vocabulary hints without
    /// being able to match the full sentence trivially — this preserves the testing
    /// and assessment value of the reading exercise.
    ///
    /// Chinese text is segmented into words using `CFStringTokenizer` (natural
    /// language-aware word boundaries). English text is split by whitespace.
    ///
    /// - Parameter text: The expected reading text.
    /// - Returns: An array of unique individual words to pass as contextual hints.
    private static func extractContextualStrings(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let words = tokenizeWords(from: trimmed)
        // Deduplicate while preserving order, filter out single characters
        var seen = Set<String>()
        var result: [String] = []
        for word in words where word.count >= 2 && !seen.contains(word) {
            seen.insert(word)
            result.append(word)
        }
        return result
    }

    /// Tokenizes a string into words using CFStringTokenizer for natural
    /// language-aware word segmentation (supports Chinese, Japanese, etc.).
    private static func tokenizeWords(from text: String) -> [String] {
        let range = CFRange(location: 0, length: text.utf16.count)
        let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault,
            text as CFString,
            range,
            kCFStringTokenizerUnitWord,
            CFLocaleCopyCurrent()
        )

        var words: [String] = []
        var tokenType = CFStringTokenizerGoToTokenAtIndex(tokenizer, 0)
        while tokenType != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if tokenRange.location != kCFNotFound, tokenRange.length > 0 {
                let start = text.utf16.index(text.utf16.startIndex, offsetBy: tokenRange.location)
                let end = text.utf16.index(start, offsetBy: tokenRange.length)
                let word = String(text[start..<end])
                words.append(word)
            }
            tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        return words
    }
}

// MARK: - SpeechRecognitionServiceDelegate
extension ReadingViewController: SpeechRecognitionServiceDelegate {
    func speechRecognitionService(_ service: Any, didProducePartialResult text: String) {
        recognizedTextLabel.text = text
        
        // Only track timing for silence detection when auto-next mode is ON.
        // When OFF, the normal manual-stop → endAudio() path is used instead.
        guard isAutoNextEnabled else { return }
        lastPartialResultTime = Date()
        lastPartialResultText = text
    }

    func speechRecognitionService(_ service: Any, didProduceFinalResult text: String) {
        recognizedTextLabel.text = text
        
        if isAutoNextEnabled && isRecording && !hasAutoAdvancedForCurrentText {
            // Auto-next mode ON: fast-path auto-advance via final result
            lastPartialResultTime = Date()
            lastPartialResultText = text
            handleAutoNextAfterFinalResult(text: text)
        } else {
            // Auto-next mode OFF (or already advanced): behave as normal —
            // enable next button so user can manually advance after stopping.
            // endAudio() will be called when user taps stop (→ stopRecording() → speechService.stopRecognition()).
            nextButton.isEnabled = true
            nextButton.alpha = 1.0
        }
    }

    func speechRecognitionService(_ service: Any, didEncounterError error: Error) {
        statusLabel.text = "错误: \(error.localizedDescription)"
        statusLabel.textColor = .errorRed
        cancelAutoNext()
        stopSilenceDetection()
        stopRecording()
    }

    func speechRecognitionServiceDidFinish(_ service: Any) {
        statusLabel.text = "识别完成"
        statusLabel.textColor = .successGreen
    }
    
    // MARK: - Silence Detection (Auto-Next Core)
    
    /// Starts a timer that periodically checks whether the user has stopped speaking.
    /// When silence exceeds `silenceThreshold`, triggers auto-next scoring.
    private func startSilenceDetection() {
        guard isAutoNextEnabled else { return }
        
        stopSilenceDetection()
        silenceDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkSilence()
        }
    }
    
    /// Stops the silence detection timer.
    private func stopSilenceDetection() {
        silenceDetectionTimer?.invalidate()
        silenceDetectionTimer = nil
    }
    
    /// Checks if the user has been silent long enough to trigger auto-next.
    private func checkSilence() {
        guard isAutoNextEnabled, isRecording, !hasAutoAdvancedForCurrentText else { return }
        guard !lastPartialResultText.isEmpty else { return }
        
        let elapsed = Date().timeIntervalSince(lastPartialResultTime)
        guard elapsed >= silenceThreshold else { return }
        
        // User has been silent for long enough — treat as finished speaking
        hasAutoAdvancedForCurrentText = true
        stopSilenceDetection()
        
        // Show countdown in indicator
        autoNextIndicator.text = "⏭ 检测到朗读结束，\(Int(autoNextDelay))秒后自动跳转..."
        autoNextIndicator.textColor = .successGreen
        
        // Schedule auto-advance after short delay
        autoNextWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.executeAutoNextFromSilence()
        }
        autoNextWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autoNextDelay, execute: workItem)
    }
    
    // MARK: - Auto-Next Logic
    
    /// Called when speech recognition produces a final result and auto-next is enabled.
    /// Scores the recognized text and auto-advances if the score meets the threshold.
    private func handleAutoNextAfterFinalResult(text: String) {
        guard let task = task, currentTextIndex < task.expectedTexts.count else { return }
        guard !hasAutoAdvancedForCurrentText else { return }
        
        let expected = task.expectedTexts[currentTextIndex]
        let result = scoringService.compare(expected: expected, actual: text)
        
        // Update the current session with scoring info
        currentSession?.recognizedText = text
        currentSession?.result = result
        
        hasAutoAdvancedForCurrentText = true
        stopSilenceDetection()
        
        if result.score >= autoNextScoreThreshold {
            autoNextIndicator.text = "⏭ 匹配度 \(Int(result.score))%，\(Int(autoNextDelay))秒后自动跳转..."
            autoNextIndicator.textColor = .successGreen
            
            autoNextWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.executeAutoNext()
            }
            autoNextWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + autoNextDelay, execute: workItem)
        } else {
            autoNextIndicator.text = "⏭ 匹配度 \(Int(result.score))% 偏低，请手动确认"
            autoNextIndicator.textColor = .warningOrange
            nextButton.isEnabled = true
            nextButton.alpha = 1.0
        }
    }
    
    /// Called from silence detection — scores the latest partial result and
    /// auto-advances if the match is good enough.
    private func executeAutoNextFromSilence() {
        guard let task = task, currentTextIndex < task.expectedTexts.count else { return }
        guard isAutoNextEnabled, hasAutoAdvancedForCurrentText else { return }
        
        let expected = task.expectedTexts[currentTextIndex]
        let actual = lastPartialResultText
        let result = scoringService.compare(expected: expected, actual: actual)
        
        // Update session with scoring info
        currentSession?.recognizedText = actual
        currentSession?.result = result
        
        if result.score >= autoNextScoreThreshold {
            executeAutoNext()
        } else {
            // Score too low — don't auto-advance, let user decide manually
            autoNextIndicator.text = "⏭ 匹配度 \(Int(result.score))% 偏低，请手动确认"
            autoNextIndicator.textColor = .warningOrange
            nextButton.isEnabled = true
            nextButton.alpha = 1.0
        }
    }
    
    /// Cancels any pending auto-advance.
    private func cancelAutoNext() {
        autoNextWorkItem?.cancel()
        autoNextWorkItem = nil
    }
    
    /// Executes the auto-advance: scores, saves session, moves to next paragraph,
    /// and optionally auto-starts recording.
    private func executeAutoNext() {
        guard let task = task, currentTextIndex < task.expectedTexts.count else { return }
        guard isAutoNextEnabled else { return }
        
        // Stop recording if still active
        if isRecording {
            speechService.stopRecognition()
            audioRecordingManager.stopRecording(keepFile: true)
            isRecording = false
            stopTimer()
            stopSilenceDetection()
        }
        
        // Score and save current session if not already done
        if let session = currentSession {
            let expected = task.expectedTexts[currentTextIndex]
            let actual = recognizedTextLabel.text ?? ""
            
            if session.result == nil {
                let result = scoringService.compare(expected: expected, actual: actual)
                session.result = result
            }
            session.recognizedText = actual
            session.endTime = Date()
            TaskManager.shared.addSession(session, toTaskId: task.id)
        }
        
        // Move to next text
        currentTextIndex += 1
        currentSession = nil
        autoNextWorkItem = nil
        
        if currentTextIndex >= task.expectedTexts.count {
            // All done
            updateContentForCurrentIndex()
            showAggregateResults()
        } else {
            updateContentForCurrentIndex()
            scrollView.setContentOffset(.zero, animated: true)
            
            // Auto-start recording for the next paragraph
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.autoStartRecordingForNextParagraph()
            }
        }
    }
    
    /// Auto-starts recording for the next paragraph when auto-next is enabled.
    private func autoStartRecordingForNextParagraph() {
        guard isAutoNextEnabled, !isRecording else { return }
        
        AudioSessionManager.shared.requestRecordingPermission { [weak self] granted in
            guard let self = self, granted else { return }
            do {
                if let oldPath = self.currentSession?.audioFilePath {
                    AudioRecordingManager.deleteAudioFile(at: oldPath)
                }
                
                let audioFilePath = try self.audioRecordingManager.startRecording()
                
                self.currentSession = ReadingSession(
                    expectedTextIndex: self.currentTextIndex,
                    audioFilePath: audioFilePath
                )
                
                let expectedText = self.task?.expectedTexts[self.currentTextIndex] ?? ""
                let contextualStrings = Self.extractContextualStrings(from: expectedText)
                try self.speechService.startRecognition(locale: Locale(identifier: "zh-CN"), contextualStrings: contextualStrings)
                
                self.isRecording = true
                self.startTimer()
                
                // Reset and start silence detection for the new paragraph
                self.lastPartialResultTime = Date()
                self.lastPartialResultText = ""
                self.hasAutoAdvancedForCurrentText = false
                if self.isAutoNextEnabled {
                    self.startSilenceDetection()
                }
                
                self.recordButton.setTitle("⏹ 停止录音", for: .normal)
                self.recordButton.backgroundColor = .textSecondary
                self.pauseButton.isEnabled = true
                self.pauseButton.alpha = 1.0
                self.statusLabel.text = "正在录音..."
                self.statusLabel.textColor = .errorRed
                self.autoNextIndicator.text = "⏭ 自动下一段已开启"
                self.autoNextIndicator.textColor = .primary
            } catch {
                self.autoNextIndicator.text = "⏭ 自动录音失败，请手动开始"
                self.autoNextIndicator.textColor = .errorRed
            }
        }
    }
}
