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

    // MARK: - Subviews
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let progressView = ReadingProgressView()
    private let expectedTextLabel = UILabel()
    private let recognizedTextLabel = UILabel()
    private let statusLabel = UILabel()
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
        } else {
            expectedTextLabel.text = "全部完成！"
            recognizedTextLabel.text = ""
            statusLabel.text = "所有文本已阅读完毕"
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
    }

    @objc private func pauseButtonTapped() {
        if speechService.isRecognizing {
            speechService.pauseRecognition()
            audioRecordingManager.pauseRecording()
            pauseButton.setTitle("▶ 继续", for: .normal)
            statusLabel.text = "已暂停"
            statusLabel.textColor = .warningOrange
            stopTimer()
        } else {
            do {
                try speechService.resumeRecognition()
                audioRecordingManager.resumeRecording()
                pauseButton.setTitle("⏸ 暂停", for: .normal)
                statusLabel.text = "正在录音..."
                statusLabel.textColor = .errorRed
                startTimer()
            } catch {
                showAlert(title: "恢复失败", message: error.localizedDescription)
            }
        }
    }

    @objc private func nextButtonTapped() {
        guard let task = task else { return }

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
    }

    func speechRecognitionService(_ service: Any, didProduceFinalResult text: String) {
        recognizedTextLabel.text = text
        nextButton.isEnabled = true
        nextButton.alpha = 1.0
    }

    func speechRecognitionService(_ service: Any, didEncounterError error: Error) {
        statusLabel.text = "错误: \(error.localizedDescription)"
        statusLabel.textColor = .errorRed
        stopRecording()
    }

    func speechRecognitionServiceDidFinish(_ service: Any) {
        statusLabel.text = "识别完成"
        statusLabel.textColor = .successGreen
    }
}
