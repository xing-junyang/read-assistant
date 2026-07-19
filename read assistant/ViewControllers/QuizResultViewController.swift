import UIKit

// MARK: - Quiz Result View Controller
/// Settlement page showing quiz score, wrong answers, and rewards.
final class QuizResultViewController: UIViewController {

    // MARK: - Properties
    private let quizSession: QuizSession
    private let questions: [QuizQuestion]
    private var levelPassed = false

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

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

        // Process result: advance level and award coins based on score tier
        let tier = quizSession.resultTier

        if tier == .completeVictory {
            // >= 90%: Complete victory — 3 coins, advance level
            WrongAnswerBookManager.shared.advanceLevel(coinsEarned: 3)
            quizSession.coinsEarned = 3
            levelPassed = true
        } else if tier == .success {
            // >= 60%: Success — no coins, advance level
            WrongAnswerBookManager.shared.advanceLevel(coinsEarned: 0)
            quizSession.coinsEarned = 0
            levelPassed = true
        } else {
            // < 60%: Failure — no advance, no coins
            quizSession.coinsEarned = -1  // Lost 1 coin to play
            levelPassed = false
        }

        // Update the session in history with coin info
        WrongAnswerBookManager.shared.recordQuizSession(quizSession)

        setupUI()
    }

    // MARK: - Computed Properties
    private var score: Int {
        return quizSession.score
    }

    private var totalQuestions: Int {
        return quizSession.totalQuestions
    }

    private var wrongItems: [(question: QuizQuestion, userAnswer: Int)] {
        var result: [(QuizQuestion, Int)] = []
        for (i, answer) in quizSession.userAnswers.enumerated() {
            if i < questions.count && answer != questions[i].correctIndex {
                result.append((questions[i], answer))
            }
        }
        return result
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "闯关结果"
        navigationItem.hidesBackButton = true

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        // Content Stack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        // Score section
        contentStack.addArrangedSubview(createScoreSection())

        // Level info section
        contentStack.addArrangedSubview(createLevelSection())

        // Wrong answers section (if any)
        if !wrongItems.isEmpty {
            let sep = createSeparator()
            contentStack.addArrangedSubview(sep)

            let wrongHeader = createSectionHeader(title: "需要复习")
            contentStack.addArrangedSubview(wrongHeader)

            for item in wrongItems {
                contentStack.addArrangedSubview(createWrongAnswerCard(for: item))
            }
        }

        // Action buttons — behavior depends on result tier
        let buttonsStack = UIStackView()
        buttonsStack.axis = .horizontal
        buttonsStack.spacing = 12
        buttonsStack.distribution = .fillEqually
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false

        let tier = quizSession.resultTier

        if tier == .failure {
            // Failure: show "重新挑战" button
            let retryButton = UIButton(type: .system)
            retryButton.setTitle("重新挑战 (-1💰)", for: .normal)
            retryButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            retryButton.backgroundColor = .warningOrange
            retryButton.setTitleColor(.white, for: .normal)
            retryButton.layer.cornerRadius = 10
            retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
            buttonsStack.addArrangedSubview(retryButton)
        } else {
            // Success or complete victory: show "继续闯关" button
            let continueButton = UIButton(type: .system)
            continueButton.setTitle("继续闯关 (-1💰)", for: .normal)
            continueButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
            continueButton.backgroundColor = .primary
            continueButton.setTitleColor(.white, for: .normal)
            continueButton.layer.cornerRadius = 10
            continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
            buttonsStack.addArrangedSubview(continueButton)
        }

        let backButton = UIButton(type: .system)
        backButton.setTitle("返回", for: .normal)
        backButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        backButton.backgroundColor = .cardBackground
        backButton.setTitleColor(.primary, for: .normal)
        backButton.layer.cornerRadius = 10
        backButton.layer.borderWidth = 1
        backButton.layer.borderColor = UIColor.primary.cgColor
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        buttonsStack.addArrangedSubview(backButton)

        contentStack.addArrangedSubview(buttonsStack)

        NSLayoutConstraint.activate([
            backButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func createScoreSection() -> UIView {
        let container = UIView()
        container.backgroundColor = .cardBackground
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let percentage = totalQuestions > 0 ? Int(Double(score) / Double(totalQuestions) * 100) : 0

        // Score circle
        let circleView = UIView()
        if percentage >= 90 {
            circleView.backgroundColor = .successGreen
        } else if percentage >= 60 {
            circleView.backgroundColor = .warningOrange
        } else {
            circleView.backgroundColor = .errorRed
        }
        circleView.layer.cornerRadius = 50
        circleView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(circleView)

        let scoreLabel = UILabel()
        scoreLabel.text = "\(score)/\(totalQuestions)"
        scoreLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        circleView.addSubview(scoreLabel)

        let percentageLabel = UILabel()
        percentageLabel.text = "正确率 \(percentage)%"
        percentageLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        percentageLabel.textColor = .textSecondary
        percentageLabel.textAlignment = .center
        percentageLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(percentageLabel)

        // Emoji feedback based on new scoring tiers
        let emojiLabel = UILabel()
        if percentage >= 90 {
            emojiLabel.text = "🎉 完全胜利！获得3金币"
        } else if percentage >= 60 {
            emojiLabel.text = "👍 闯关成功！进入下一关"
        } else {
            emojiLabel.text = "📚 闯关失败，请继续加油！"
        }
        emojiLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        emojiLabel.textColor = .textPrimary
        emojiLabel.textAlignment = .center
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(emojiLabel)

        NSLayoutConstraint.activate([
            circleView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            circleView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            circleView.widthAnchor.constraint(equalToConstant: 100),
            circleView.heightAnchor.constraint(equalToConstant: 100),

            scoreLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            scoreLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor),

            percentageLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 12),
            percentageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            emojiLabel.topAnchor.constraint(equalTo: percentageLabel.bottomAnchor, constant: 8),
            emojiLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emojiLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])

        return container
    }

    private func createLevelSection() -> UIView {
        let container = UIView()
        container.backgroundColor = .cardBackground
        container.layer.cornerRadius = 12
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let tier = quizSession.resultTier
        let levelCompleted = WrongAnswerBookManager.shared.totalLevelsCompleted

        // Result tier label
        let resultLabel = UILabel()
        switch tier {
        case .completeVictory:
            resultLabel.text = "🏆 完全胜利！第 \(quizSession.levelNumber) 关通过"
            resultLabel.textColor = .successGreen
        case .success:
            resultLabel.text = "✅ 闯关成功！第 \(quizSession.levelNumber) 关通过"
            resultLabel.textColor = .warningOrange
        case .failure:
            resultLabel.text = "❌ 闯关失败！第 \(quizSession.levelNumber) 关未通过"
            resultLabel.textColor = .errorRed
        }
        resultLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        stack.addArrangedSubview(resultLabel)

        // Level display
        let levelLabel = UILabel()
        levelLabel.text = "🏆 当前进度：已完成第 \(levelCompleted) 关"
        levelLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        levelLabel.textColor = .textSecondary
        stack.addArrangedSubview(levelLabel)

        // Coin info
        let coinInfo = UILabel()
        var coinMessages: [String] = []
        let tierCoinChange = quizSession.coinsEarned
        if tier == .completeVictory {
            coinMessages.append("🎁 本关奖励：+\(tierCoinChange)金币")
        } else if tier == .failure {
            coinMessages.append("💸 本关消耗：1金币")
        } else {
            coinMessages.append("➖ 本关无金币奖励")
        }

        // Milestone info
        if levelCompleted > 0 && levelCompleted % 10 == 0 {
            coinMessages.append("🎁 第\(levelCompleted)关里程碑奖励：+20金币")
        }
        if levelCompleted > 0 && levelCompleted % 100 == 0 {
            coinMessages.append("🎁 第\(levelCompleted)关里程碑奖励：+50金币")
        }

        coinMessages.append("💰 当前金币：\(RewardManager.shared.coins)")
        coinInfo.text = coinMessages.joined(separator: "\n")
        coinInfo.font = UIFont.systemFont(ofSize: 14)
        coinInfo.textColor = .textSecondary
        coinInfo.numberOfLines = 0
        stack.addArrangedSubview(coinInfo)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        return container
    }

    private func createWrongAnswerCard(for item: (QuizQuestion, Int)) -> UIView {
        let container = UIView()
        container.backgroundColor = .cardBackground
        container.layer.cornerRadius = 10
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.errorRed.withAlphaComponent(0.3).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        let question = item.0
        let userAnswerIndex = item.1

        // Question type indicator
        let typeLabel = UILabel()
        typeLabel.text = question.questionType == .characterToPinyin ? "📖 看字选拼音" : "🔤 看拼音选字"
        typeLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        typeLabel.textColor = .textSecondary
        stack.addArrangedSubview(typeLabel)

        // Prompt
        let promptLabel = UILabel()
        if question.questionType == .characterToPinyin {
            promptLabel.text = "字词: \(question.sourceItem.correctText)"
        } else {
            promptLabel.text = "拼音: \(question.sourceItem.correctPinyin)"
        }
        promptLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        promptLabel.textColor = .textPrimary
        stack.addArrangedSubview(promptLabel)

        // Correct answer
        let correctLabel = UILabel()
        correctLabel.text = "✅ 正确答案: \(question.options[question.correctIndex])"
        correctLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        correctLabel.textColor = .successGreen
        stack.addArrangedSubview(correctLabel)

        // User answer
        if userAnswerIndex >= 0 && userAnswerIndex < question.options.count {
            let userLabel = UILabel()
            userLabel.text = "❌ 你的选择: \(question.options[userAnswerIndex])"
            userLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
            userLabel.textColor = .errorRed
            stack.addArrangedSubview(userLabel)
        }

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func createSectionHeader(title: String) -> UIView {
        let container = UIView()
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        label.textColor = .textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    private func createSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    // MARK: - Actions
    @objc private func continueTapped() {
        // Check coins before continuing
        guard RewardManager.shared.coins >= 1 else {
            let alert = UIAlertController(
                title: "金币不足",
                message: "闯关需要消耗1金币，你当前有\(RewardManager.shared.coins)金币。请先完成阅读练习获取金币。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        // Deduct 1 coin
        RewardManager.shared.spendCoins(1)

        // Start a new quiz level
        WrongAnswerBookManager.shared.syncWrongAnswers()
        WrongAnswerBookManager.shared.waitForSync { [weak self] in
            guard let self = self else { return }
            let manager = WrongAnswerBookManager.shared

            guard let newQuestions = manager.generateQuizLevel() else {
                let alert = UIAlertController(
                    title: "无法继续",
                    message: "错题本中至少需要4个字词才能开始闯关。",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert, animated: true)
                return
            }

            let levelNumber = manager.totalLevelsCompleted + 1
            let quizData = newQuestions.map { q -> QuizQuestionData in
                return QuizQuestionData(
                    correctAnswer: q.correctAnswer,
                    options: q.options,
                    correctIndex: q.correctIndex,
                    questionType: q.questionType.rawValue,
                    sourceItemID: q.sourceItem.id
                )
            }
            let session = QuizSession(levelNumber: levelNumber, questions: quizData)

            let quizVC = QuizViewController(quizSession: session, questions: newQuestions)

            // Replace current navigation stack: pop result, push quiz
            if var viewControllers = self.navigationController?.viewControllers {
                viewControllers.removeLast()
                viewControllers.append(quizVC)
                self.navigationController?.setViewControllers(viewControllers, animated: true)
            }
        }
    }

    @objc private func retryTapped() {
        // Re-challenge the same level — check coins first
        guard RewardManager.shared.coins >= 1 else {
            let alert = UIAlertController(
                title: "金币不足",
                message: "闯关需要消耗1金币，你当前有\(RewardManager.shared.coins)金币。请先完成阅读练习获取金币。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        // Deduct 1 coin
        RewardManager.shared.spendCoins(1)

        // Start a new quiz at the same level
        WrongAnswerBookManager.shared.syncWrongAnswers()
        WrongAnswerBookManager.shared.waitForSync { [weak self] in
            guard let self = self else { return }
            let manager = WrongAnswerBookManager.shared

            guard let newQuestions = manager.generateQuizLevel() else {
                let alert = UIAlertController(
                    title: "无法继续",
                    message: "错题本中至少需要4个字词才能开始闯关。",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "确定", style: .default))
                self.present(alert, animated: true)
                return
            }

            // Same level number (since level wasn't advanced)
            let levelNumber = manager.totalLevelsCompleted + 1
            let quizData = newQuestions.map { q -> QuizQuestionData in
                return QuizQuestionData(
                    correctAnswer: q.correctAnswer,
                    options: q.options,
                    correctIndex: q.correctIndex,
                    questionType: q.questionType.rawValue,
                    sourceItemID: q.sourceItem.id
                )
            }
            let session = QuizSession(levelNumber: levelNumber, questions: quizData)

            let quizVC = QuizViewController(quizSession: session, questions: newQuestions)

            if var viewControllers = self.navigationController?.viewControllers {
                viewControllers.removeLast()
                viewControllers.append(quizVC)
                self.navigationController?.setViewControllers(viewControllers, animated: true)
            }
        }
    }

    @objc private func backTapped() {
        // Go back to the challenge menu
        navigationController?.popToRootViewController(animated: true)
    }
}
