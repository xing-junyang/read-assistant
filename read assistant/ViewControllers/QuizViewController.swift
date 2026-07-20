import UIKit

// MARK: - Quiz View Controller
/// Handles the quiz gameplay: shows questions one at a time,
/// two question types (看字选拼音 and 看拼音选字), single choice 4 options.
/// Correct answers auto-advance to the next question after a short delay.
final class QuizViewController: UIViewController {

    // MARK: - Properties
    private let quizSession: QuizSession
    private let questions: [QuizQuestion]
    private var currentIndex = 0
    private var selectedAnswerIndex: Int? = nil
    private let isSmallScreen = UIScreen.main.bounds.height <= 667  // iPhone SE, 6, 7, 8

    /// Delay before auto-advancing after a correct answer (seconds).
    private let autoAdvanceDelay: TimeInterval = 0.6
    /// Prevents double-tap during auto-advance transition.
    private var isAutoAdvancing = false

    // MARK: - Subviews
    private let progressBar = UIProgressView(progressViewStyle: .bar)
    private let progressLabel = UILabel()
    private let questionTypeLabel = UILabel()
    private let questionContentView = UIView()
    private let questionTextLabel = UILabel()
    private let pinyinLabel = UILabel()
    private let optionsStack = UIStackView()
    private var optionButtons: [UIButton] = []
    private let nextButton = UIButton(type: .system)

    // MARK: - Colors
    private let correctColor = UIColor.successGreen
    private let wrongColor = UIColor.errorRed
    private let defaultOptionColor = UIColor.cardBackground
    private let selectedColor = UIColor.primaryLight.withAlphaComponent(0.3)

    // MARK: - Initialization
    init(quizSession: QuizSession, questions: [QuizQuestion]) {
        self.quizSession = quizSession
        self.questions = questions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        showQuestion(at: 0)
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "词语闯关 第\(quizSession.levelNumber)关"
        navigationItem.hidesBackButton = false

        // Progress bar
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.trackTintColor = .separator
        progressBar.progressTintColor = .primary
        view.addSubview(progressBar)

        progressLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        progressLabel.textColor = .textSecondary
        progressLabel.textAlignment = .center
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressLabel)

        // Question type label
        questionTypeLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        questionTypeLabel.textColor = .primary
        questionTypeLabel.textAlignment = .center
        questionTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(questionTypeLabel)

        // Question content card
        questionContentView.backgroundColor = .cardBackground
        questionContentView.layer.cornerRadius = 12
        questionContentView.layer.shadowColor = UIColor.black.cgColor
        questionContentView.layer.shadowOffset = CGSize(width: 0, height: 2)
        questionContentView.layer.shadowRadius = 6
        questionContentView.layer.shadowOpacity = 0.08
        questionContentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(questionContentView)

        // Question text (large character or pinyin)
        questionTextLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        questionTextLabel.textColor = .textPrimary
        questionTextLabel.textAlignment = .center
        questionTextLabel.numberOfLines = 3
        questionTextLabel.translatesAutoresizingMaskIntoConstraints = false
        questionContentView.addSubview(questionTextLabel)

        // Pinyin sub-label (for character-to-pinyin questions)
        pinyinLabel.font = UIFont.systemFont(ofSize: 16)
        pinyinLabel.textColor = .textSecondary
        pinyinLabel.textAlignment = .center
        pinyinLabel.isHidden = true
        pinyinLabel.translatesAutoresizingMaskIntoConstraints = false
        questionContentView.addSubview(pinyinLabel)

        // Options stack - vertical container holding 2 horizontal rows (2x2 grid)
        optionsStack.axis = .vertical
        optionsStack.spacing = 12
        optionsStack.distribution = .fillEqually
        optionsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(optionsStack)

        // Create 2x2 grid: 2 rows, each with 2 buttons
        let buttonFontSize: CGFloat = isSmallScreen ? 17 : 20
        let buttonHeight: CGFloat = isSmallScreen ? 48 : 56

        for rowIndex in 0..<2 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 12
            rowStack.distribution = .fillEqually
            optionsStack.addArrangedSubview(rowStack)

            for colIndex in 0..<2 {
                let i = rowIndex * 2 + colIndex
                let button = UIButton(type: .system)
                button.backgroundColor = defaultOptionColor
                button.setTitleColor(.textPrimary, for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: buttonFontSize, weight: .medium)
                button.layer.cornerRadius = 10
                button.layer.borderWidth = 2
                button.layer.borderColor = UIColor.separator.cgColor
                button.tag = i
                button.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
                button.translatesAutoresizingMaskIntoConstraints = false
                button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
                optionButtons.append(button)
                rowStack.addArrangedSubview(button)
            }
        }

        // Next / Finish button
        nextButton.setTitle("下一题", for: .normal)
        nextButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        nextButton.backgroundColor = .primary
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.layer.cornerRadius = 10
        nextButton.isHidden = true
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nextButton)

        // Layout
        let cardMinHeight: CGFloat = isSmallScreen ? 90 : 120
        let questionTextTopPadding: CGFloat = isSmallScreen ? 12 : 24
        let questionTypeTopSpacing: CGFloat = isSmallScreen ? 6 : 12
        let questionCardTopSpacing: CGFloat = isSmallScreen ? 8 : 16
        let optionsTopSpacing: CGFloat = isSmallScreen ? 12 : 20

        NSLayoutConstraint.activate([
            progressBar.topAnchor.constraint(equalTo: compatSafeAreaTop, constant: 8),
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            progressLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 6),
            progressLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            questionTypeLabel.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: questionTypeTopSpacing),
            questionTypeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            questionContentView.topAnchor.constraint(equalTo: questionTypeLabel.bottomAnchor, constant: questionCardTopSpacing),
            questionContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            questionContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            questionContentView.heightAnchor.constraint(greaterThanOrEqualToConstant: cardMinHeight),

            questionTextLabel.topAnchor.constraint(equalTo: questionContentView.topAnchor, constant: questionTextTopPadding),
            questionTextLabel.leadingAnchor.constraint(equalTo: questionContentView.leadingAnchor, constant: 16),
            questionTextLabel.trailingAnchor.constraint(equalTo: questionContentView.trailingAnchor, constant: -16),

            pinyinLabel.topAnchor.constraint(equalTo: questionTextLabel.bottomAnchor, constant: 8),
            pinyinLabel.leadingAnchor.constraint(equalTo: questionContentView.leadingAnchor, constant: 16),
            pinyinLabel.trailingAnchor.constraint(equalTo: questionContentView.trailingAnchor, constant: -16),
            pinyinLabel.bottomAnchor.constraint(equalTo: questionContentView.bottomAnchor, constant: -20),

            optionsStack.topAnchor.constraint(equalTo: questionContentView.bottomAnchor, constant: optionsTopSpacing),
            optionsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            optionsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            nextButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            nextButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            nextButton.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -16),
            nextButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    // MARK: - Question Display
    private func showQuestion(at index: Int, animated: Bool = true) {
        guard index < questions.count else { return }
        currentIndex = index
        selectedAnswerIndex = nil
        isAutoAdvancing = false

        let question = questions[index]

        let applyChanges = {
            // Update progress
            self.progressBar.progress = Float(index) / Float(self.questions.count)
            self.progressLabel.text = "\(index + 1) / \(self.questions.count)"

            // Reset option buttons
            for button in self.optionButtons {
                button.backgroundColor = self.defaultOptionColor
                button.layer.borderColor = UIColor.separator.cgColor
                button.setTitleColor(.textPrimary, for: .normal)
                button.isEnabled = true
                button.alpha = 1.0
            }
            self.nextButton.isHidden = true

            // Configure question based on type
            if question.questionType == .characterToPinyin {
                // 看字选拼音
                self.questionTypeLabel.text = "📖 看字选拼音"
                self.questionTextLabel.text = question.sourceItem.correctText
                self.questionTextLabel.font = UIFont.systemFont(ofSize: self.isSmallScreen ? 36 : 48, weight: .bold)
                self.pinyinLabel.isHidden = false
                self.pinyinLabel.text = "请选择正确的拼音"
            } else {
                // 看拼音选字
                self.questionTypeLabel.text = "🔤 看拼音选字"
                // Show tone-marked pinyin as the prompt
                self.questionTextLabel.text = question.sourceItem.correctPinyin
                self.questionTextLabel.font = UIFont.systemFont(ofSize: self.isSmallScreen ? 28 : 36, weight: .bold)
                self.pinyinLabel.isHidden = false
                self.pinyinLabel.text = "请选择正确的汉字"
            }

            // Set option texts with shuffled order
            for i in 0..<4 {
                if i < question.options.count {
                    self.optionButtons[i].setTitle(question.options[i], for: .normal)
                    self.optionButtons[i].isHidden = false
                } else {
                    self.optionButtons[i].isHidden = true
                }
            }
        }

        if animated {
            UIView.transition(with: questionContentView, duration: 0.25, options: .transitionCrossDissolve, animations: {
                applyChanges()
            }, completion: nil)

            UIView.transition(with: optionsStack, duration: 0.25, options: .transitionCrossDissolve, animations: {
                // Options are updated inside applyChanges
            }, completion: nil)
        } else {
            applyChanges()
        }
    }

    // MARK: - Actions
    @objc private func optionTapped(_ sender: UIButton) {
        guard selectedAnswerIndex == nil, !isAutoAdvancing else { return }

        let selectedIndex = sender.tag
        selectedAnswerIndex = selectedIndex

        let question = questions[currentIndex]
        let isCorrect = selectedIndex == question.correctIndex

        // Record answer
        quizSession.userAnswers[currentIndex] = selectedIndex

        // Sound effect and haptic feedback
        if isCorrect {
            SoundEffectManager.shared.playQuizCorrectSound()
            triggerHaptic(.success)
        } else {
            SoundEffectManager.shared.playQuizIncorrectSound()
            triggerHaptic(.error)
        }

        // Highlight correct and wrong answers
        for (i, button) in optionButtons.enumerated() {
            button.isEnabled = false
            if i == question.correctIndex {
                // Correct answer always shown green
                button.backgroundColor = correctColor.withAlphaComponent(0.2)
                button.layer.borderColor = correctColor.cgColor
                button.setTitleColor(correctColor, for: .normal)
            } else if i == selectedIndex && !isCorrect {
                // Wrong selection shown red
                button.backgroundColor = wrongColor.withAlphaComponent(0.15)
                button.layer.borderColor = wrongColor.cgColor
                button.setTitleColor(wrongColor, for: .normal)
            } else {
                // Other options dimmed
                button.alpha = 0.4
            }
        }

        if isCorrect {
            // Auto-advance after a short delay on correct answer
            isAutoAdvancing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + autoAdvanceDelay) { [weak self] in
                guard let self = self else { return }
                self.advanceToNext()
            }
        } else {
            // Show next/finish button for incorrect answers
            if currentIndex < questions.count - 1 {
                nextButton.setTitle("下一题", for: .normal)
            } else {
                nextButton.setTitle("查看结果", for: .normal)
            }
            nextButton.isHidden = false

            // Animate next button appearance
            nextButton.alpha = 0
            UIView.animate(withDuration: 0.3) {
                self.nextButton.alpha = 1
            }
        }
    }

    private func advanceToNext() {
        isAutoAdvancing = false
        if currentIndex < questions.count - 1 {
            showQuestion(at: currentIndex + 1)
        } else {
            finishQuiz()
        }
    }

    /// Triggers haptic feedback compatible with iOS 10+.
    private func triggerHaptic(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    @objc private func nextTapped() {
        guard !isAutoAdvancing else { return }
        advanceToNext()
    }

    // MARK: - Finish
    private func finishQuiz() {
        quizSession.endTime = Date()
        quizSession.isCompleted = true

        let resultVC = QuizResultViewController(quizSession: quizSession, questions: questions)
        navigationController?.pushViewController(resultVC, animated: true)
    }
}
