import UIKit

// MARK: - Character Scramble View Controller
/// Word scramble game: characters from a wrong-answer-book word are scrambled,
/// player must tap them in the correct order to rebuild the word.
/// Pinyin is shown as a hint. Costs 10 coins per play.
final class CharacterScrambleViewController: UIViewController {

    // MARK: - Properties
    /// Pool of words from wrong answer book: (word, pinyin)
    private var wordPool: [(word: String, pinyin: String)] = []
    private var currentWordIndex = 0
    private var score = 0
    private var roundCount = 0
    private let maxRounds = 10
    private var timeLeft = 60
    private var timer: Timer?
    private var isGameOver = false

    /// Current round state
    private var currentWord = ""
    private var currentPinyin = ""
    private var scrambledChars: [String] = []
    private var selectedIndices: [Int] = []  // Ordered indices of tapped chars

    // MARK: - Subviews
    private let headerView = UIView()
    private let scoreLabel = UILabel()
    private let roundLabel = UILabel()
    private let timerLabel = UILabel()

    private let hintCard = UIView()
    private let pinyinLabel = UILabel()
    private let charCountLabel = UILabel()

    private let answerSlotsStack = UIStackView()
    private var slotLabels: [UILabel] = []

    private let charButtonsStack = UIStackView()
    private var charButtons: [UIButton] = []

    private let clearButton = UIButton(type: .system)
    private let submitButton = UIButton(type: .system)

    private let gameOverView = UIView()
    private let gameOverTitleLabel = UILabel()
    private let gameOverScoreLabel = UILabel()
    private let restartButton = UIButton(type: .system)
    private let exitButton = UIButton(type: .system)

    // MARK: - Initialization
    init() {
        super.init(nibName: nil, bundle: nil)
        buildWordPool()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startGame()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Word Pool
    private func buildWordPool() {
        let wrongAnswers = WrongAnswerBookManager.shared.wrongAnswers
        for item in wrongAnswers {
            let text = item.correctText.trimmingCharacters(in: .whitespaces)
            // Only use 2-4 character CJK words
            guard text.count >= 2, text.count <= 4 else { continue }
            guard text.unicodeScalars.allSatisfy({
                ($0.value >= 0x4E00 && $0.value <= 0x9FFF) || ($0.value >= 0x3400 && $0.value <= 0x4DBF)
            }) else { continue }

            let py = pinyinOf(text)
            guard !py.isEmpty, py != text.lowercased() else { continue }
            wordPool.append((word: text, pinyin: py))
        }
        wordPool.shuffle()
    }

    private func pinyinOf(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        return (mutable as String).lowercased().replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Game Logic
    private func startGame() {
        score = 0
        roundCount = 0
        timeLeft = 60
        isGameOver = false

        guard !wordPool.isEmpty else {
            showNoWordsAlert()
            return
        }

        currentWordIndex = 0
        loadRound()
        startTimer()
        updateHeader()
    }

    private func showNoWordsAlert() {
        let alert = UIAlertController(
            title: "无法开始",
            message: "错题本中至少需要一些2-4字的词语才能开始游戏。请先完成一些阅读练习。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "返回", style: .default) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.isGameOver else { return }
            self.timeLeft -= 1
            self.updateHeader()
            if self.timeLeft <= 0 {
                self.endGame()
            }
        }
    }

    private func loadRound() {
        if currentWordIndex >= wordPool.count {
            // Cycle through pool
            currentWordIndex = 0
            wordPool.shuffle()
            if currentWordIndex >= wordPool.count {
                endGame()
                return
            }
        }

        let pair = wordPool[currentWordIndex]
        currentWord = pair.word
        currentPinyin = pair.pinyin
        currentWordIndex += 1

        // Scramble the characters
        let chars = currentWord.map { String($0) }
        scrambledChars = chars.shuffled()
        selectedIndices.removeAll()

        updateRoundUI()
    }

    private func updateRoundUI() {
        pinyinLabel.text = currentPinyin
        charCountLabel.text = "\(currentWord.count) 个字"

        // Update slots
        for (i, label) in slotLabels.enumerated() {
            if i < selectedIndices.count {
                let charIndex = selectedIndices[i]
                label.text = scrambledChars[charIndex]
                label.textColor = .textPrimary
                label.backgroundColor = .primaryLight.withAlphaComponent(0.2)
            } else if i < currentWord.count {
                label.text = "_"
                label.textColor = .textTertiary
                label.backgroundColor = .clear
            } else {
                label.text = ""
                label.backgroundColor = .clear
            }
        }

        // Update char buttons
        for (i, button) in charButtons.enumerated() {
            if i < scrambledChars.count {
                button.setTitle(scrambledChars[i], for: .normal)
                button.isHidden = false
                button.isEnabled = !selectedIndices.contains(i)
                button.alpha = selectedIndices.contains(i) ? 0.3 : 1.0
            } else {
                button.isHidden = true
            }
        }

        // Enable/disable submit
        submitButton.isEnabled = selectedIndices.count == currentWord.count
        submitButton.alpha = submitButton.isEnabled ? 1.0 : 0.5

        clearButton.isEnabled = !selectedIndices.isEmpty
        clearButton.alpha = clearButton.isEnabled ? 1.0 : 0.5
    }

    @objc private func charButtonTapped(_ sender: UIButton) {
        guard !isGameOver else { return }
        let index = sender.tag
        guard index < scrambledChars.count, !selectedIndices.contains(index) else { return }

        selectedIndices.append(index)
        updateRoundUI()
    }

    @objc private func clearTapped() {
        guard !isGameOver else { return }
        selectedIndices.removeAll()
        updateRoundUI()
    }

    @objc private func submitTapped() {
        guard !isGameOver, selectedIndices.count == currentWord.count else { return }

        // Build the player's answer
        let playerWord = selectedIndices.map { scrambledChars[$0] }.joined()

        if playerWord == currentWord {
            // Correct!
            score += 10
            roundCount += 1
            timeLeft = min(timeLeft + 5, 60)

            // Flash success
            flashSlots(.successGreen)
        } else {
            // Wrong
            // Flash error and show correct answer briefly
            flashSlots(.errorRed)
        }

        if roundCount >= maxRounds {
            endGame()
            return
        }

        // Load next round after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self, !self.isGameOver else { return }
            self.loadRound()
            self.updateHeader()
        }
    }

    private func flashSlots(_ color: UIColor) {
        UIView.animate(withDuration: 0.2, animations: {
            self.slotLabels.forEach { $0.backgroundColor = color.withAlphaComponent(0.3) }
        }) { _ in
            UIView.animate(withDuration: 0.3) {
                self.slotLabels.forEach { $0.backgroundColor = .clear }
            }
        }
    }

    private func endGame() {
        isGameOver = true
        timer?.invalidate()
        timer = nil
        submitButton.isEnabled = false
        clearButton.isEnabled = false
        charButtons.forEach { $0.isEnabled = false }

        // Reward: 2x cost on success
        let costCoins = DeveloperSettingsManager.shared.effectiveIdiomChainCostCoins
        let rewardCoins: Int
        if score >= 80 {
            rewardCoins = costCoins * 2  // 2x cost
        } else if score >= 50 {
            rewardCoins = costCoins
        } else {
            rewardCoins = 0
        }

        if rewardCoins > 0 {
            RewardManager.shared.coins += rewardCoins
        }

        gameOverTitleLabel.text = score >= 50 ? "🎉 挑战结束" : "⏰ 时间到"
        gameOverScoreLabel.text = "得分：\(score) 分\n拼对：\(roundCount) 个词语\n获得金币：\(rewardCoins)💰"
        gameOverView.isHidden = false
    }

    // MARK: - UI Updates
    private func updateHeader() {
        scoreLabel.text = "⭐️ \(score) 分"
        roundLabel.text = "📝 \(roundCount)/\(maxRounds) 题"
        timerLabel.text = "⏱ \(timeLeft) 秒"
        timerLabel.textColor = timeLeft <= 10 ? .errorRed : .accent
    }

    // MARK: - Actions
    @objc private func restartTapped() {
        let costCoins = DeveloperSettingsManager.shared.effectiveIdiomChainCostCoins
        let currentCoins = RewardManager.shared.coins

        guard currentCoins >= costCoins else {
            let alert = UIAlertController(
                title: "金币不足",
                message: "需要\(costCoins)金币才能再玩一次，你当前有\(currentCoins)金币。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        guard RewardManager.shared.spendCoins(costCoins) else { return }

        gameOverView.isHidden = true
        wordPool.shuffle()
        startGame()
    }

    @objc private func exitTapped() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "汉字拼图"
        navigationItem.hidesBackButton = true

        // ===== HEADER =====
        headerView.backgroundColor = .cardBackground
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        scoreLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        scoreLabel.textColor = .accent
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(scoreLabel)

        roundLabel.font = UIFont.systemFont(ofSize: 14)
        roundLabel.textColor = .textSecondary
        roundLabel.textAlignment = .center
        roundLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(roundLabel)

        timerLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        timerLabel.textColor = .accent
        timerLabel.textAlignment = .right
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(timerLabel)

        // ===== HINT CARD =====
        hintCard.backgroundColor = .cardBackground
        hintCard.layer.cornerRadius = 12
        hintCard.layer.shadowColor = UIColor.black.cgColor
        hintCard.layer.shadowOffset = CGSize(width: 0, height: 2)
        hintCard.layer.shadowRadius = 6
        hintCard.layer.shadowOpacity = 0.08
        hintCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintCard)

        let hintTitleLabel = UILabel()
        hintTitleLabel.text = "拼音提示"
        hintTitleLabel.font = UIFont.systemFont(ofSize: 13)
        hintTitleLabel.textColor = .textTertiary
        hintTitleLabel.textAlignment = .center
        hintTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        hintCard.addSubview(hintTitleLabel)

        pinyinLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        pinyinLabel.textColor = .primary
        pinyinLabel.textAlignment = .center
        pinyinLabel.translatesAutoresizingMaskIntoConstraints = false
        hintCard.addSubview(pinyinLabel)

        charCountLabel.font = UIFont.systemFont(ofSize: 14)
        charCountLabel.textColor = .textSecondary
        charCountLabel.textAlignment = .center
        charCountLabel.translatesAutoresizingMaskIntoConstraints = false
        hintCard.addSubview(charCountLabel)

        // ===== ANSWER SLOTS =====
        answerSlotsStack.axis = .horizontal
        answerSlotsStack.spacing = 8
        answerSlotsStack.distribution = .fillEqually
        answerSlotsStack.alignment = .center
        answerSlotsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(answerSlotsStack)

        // Create 4 slot labels (max word length)
        for i in 0..<4 {
            let label = UILabel()
            label.text = "_"
            label.font = UIFont.systemFont(ofSize: 32, weight: .bold)
            label.textColor = .textTertiary
            label.textAlignment = .center
            label.layer.cornerRadius = 8
            label.layer.borderWidth = 1.5
            label.layer.borderColor = UIColor.separator.cgColor
            label.clipsToBounds = true
            label.tag = i
            label.translatesAutoresizingMaskIntoConstraints = false
            label.heightAnchor.constraint(equalToConstant: 52).isActive = true
            slotLabels.append(label)
            answerSlotsStack.addArrangedSubview(label)
        }

        // ===== CHAR BUTTONS =====
        charButtonsStack.axis = .horizontal
        charButtonsStack.spacing = 10
        charButtonsStack.distribution = .fillEqually
        charButtonsStack.alignment = .center
        charButtonsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(charButtonsStack)

        for i in 0..<4 {
            let button = UIButton(type: .system)
            button.setTitle("字", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .bold)
            button.setTitleColor(.textPrimary, for: .normal)
            button.backgroundColor = .cardBackground
            button.layer.cornerRadius = 10
            button.layer.borderWidth = 2
            button.layer.borderColor = UIColor.separator.cgColor
            button.tag = i
            button.addTarget(self, action: #selector(charButtonTapped(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 56).isActive = true
            charButtons.append(button)
            charButtonsStack.addArrangedSubview(button)
        }

        // ===== ACTION BUTTONS =====
        clearButton.setTitle("清空", for: .normal)
        clearButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        clearButton.setTitleColor(.textSecondary, for: .normal)
        clearButton.backgroundColor = .separator
        clearButton.layer.cornerRadius = 8
        clearButton.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearButton)

        submitButton.setTitle("提交", for: .normal)
        submitButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        submitButton.backgroundColor = .primary
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.layer.cornerRadius = 8
        submitButton.isEnabled = false
        submitButton.alpha = 0.5
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(submitButton)

        // ===== GAME OVER OVERLAY =====
        gameOverView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        gameOverView.isHidden = true
        gameOverView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gameOverView)

        let goCard = UIView()
        goCard.backgroundColor = .cardBackground
        goCard.layer.cornerRadius = 16
        goCard.translatesAutoresizingMaskIntoConstraints = false
        gameOverView.addSubview(goCard)

        gameOverTitleLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        gameOverTitleLabel.textColor = .textPrimary
        gameOverTitleLabel.textAlignment = .center
        gameOverTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        goCard.addSubview(gameOverTitleLabel)

        gameOverScoreLabel.font = UIFont.systemFont(ofSize: 18)
        gameOverScoreLabel.textColor = .textSecondary
        gameOverScoreLabel.textAlignment = .center
        gameOverScoreLabel.numberOfLines = 3
        gameOverScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        goCard.addSubview(gameOverScoreLabel)

        let costCoins = DeveloperSettingsManager.shared.effectiveIdiomChainCostCoins
        restartButton.setTitle("再来一局 (-\(costCoins)💰)", for: .normal)
        restartButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        restartButton.backgroundColor = .primary
        restartButton.setTitleColor(.white, for: .normal)
        restartButton.layer.cornerRadius = 8
        restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)
        restartButton.translatesAutoresizingMaskIntoConstraints = false
        goCard.addSubview(restartButton)

        exitButton.setTitle("返回", for: .normal)
        exitButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        exitButton.setTitleColor(.textSecondary, for: .normal)
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        exitButton.translatesAutoresizingMaskIntoConstraints = false
        goCard.addSubview(exitButton)

        // ===== LAYOUT =====
        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),

            scoreLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            scoreLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            roundLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            roundLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            timerLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            timerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // Hint card
            hintCard.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 20),
            hintCard.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintCard.widthAnchor.constraint(equalToConstant: 280),
            hintCard.heightAnchor.constraint(equalToConstant: 100),

            hintTitleLabel.topAnchor.constraint(equalTo: hintCard.topAnchor, constant: 12),
            hintTitleLabel.centerXAnchor.constraint(equalTo: hintCard.centerXAnchor),

            pinyinLabel.topAnchor.constraint(equalTo: hintTitleLabel.bottomAnchor, constant: 4),
            pinyinLabel.centerXAnchor.constraint(equalTo: hintCard.centerXAnchor),

            charCountLabel.topAnchor.constraint(equalTo: pinyinLabel.bottomAnchor, constant: 4),
            charCountLabel.centerXAnchor.constraint(equalTo: hintCard.centerXAnchor),

            // Answer slots
            answerSlotsStack.topAnchor.constraint(equalTo: hintCard.bottomAnchor, constant: 28),
            answerSlotsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            answerSlotsStack.widthAnchor.constraint(equalToConstant: 280),
            answerSlotsStack.heightAnchor.constraint(equalToConstant: 52),

            // Char buttons
            charButtonsStack.topAnchor.constraint(equalTo: answerSlotsStack.bottomAnchor, constant: 24),
            charButtonsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            charButtonsStack.widthAnchor.constraint(equalToConstant: 300),
            charButtonsStack.heightAnchor.constraint(equalToConstant: 56),

            // Action buttons
            clearButton.topAnchor.constraint(equalTo: charButtonsStack.bottomAnchor, constant: 28),
            clearButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            clearButton.widthAnchor.constraint(equalToConstant: 100),
            clearButton.heightAnchor.constraint(equalToConstant: 44),

            submitButton.topAnchor.constraint(equalTo: charButtonsStack.bottomAnchor, constant: 28),
            submitButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            submitButton.leadingAnchor.constraint(equalTo: clearButton.trailingAnchor, constant: 16),
            submitButton.heightAnchor.constraint(equalToConstant: 44),

            // Game over
            gameOverView.topAnchor.constraint(equalTo: view.topAnchor),
            gameOverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gameOverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gameOverView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            goCard.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            goCard.centerYAnchor.constraint(equalTo: gameOverView.centerYAnchor),
            goCard.widthAnchor.constraint(equalToConstant: 280),
            goCard.heightAnchor.constraint(equalToConstant: 240),

            gameOverTitleLabel.topAnchor.constraint(equalTo: goCard.topAnchor, constant: 28),
            gameOverTitleLabel.centerXAnchor.constraint(equalTo: goCard.centerXAnchor),

            gameOverScoreLabel.topAnchor.constraint(equalTo: gameOverTitleLabel.bottomAnchor, constant: 16),
            gameOverScoreLabel.centerXAnchor.constraint(equalTo: goCard.centerXAnchor),

            restartButton.topAnchor.constraint(equalTo: gameOverScoreLabel.bottomAnchor, constant: 24),
            restartButton.centerXAnchor.constraint(equalTo: goCard.centerXAnchor),
            restartButton.widthAnchor.constraint(equalToConstant: 200),
            restartButton.heightAnchor.constraint(equalToConstant: 44),

            exitButton.topAnchor.constraint(equalTo: restartButton.bottomAnchor, constant: 8),
            exitButton.centerXAnchor.constraint(equalTo: goCard.centerXAnchor),
        ])
    }
}
