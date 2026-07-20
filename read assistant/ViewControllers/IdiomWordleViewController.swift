import UIKit

// MARK: - Idiom Wordle View Controller
/// Chinese Wordle-style game: guess a 4-character idiom (成语) in 6 attempts.
/// After each guess, each character gets color feedback:
///   🟢 Green — correct character, correct position
///   🟡 Yellow — correct character, wrong position
///   ⚪ Gray — character not in the idiom
/// 49 candidate characters are shown as a picker palette.
/// Costs 15 coins per play (configurable).
final class IdiomWordleViewController: UIViewController {

    // MARK: - Guess Result
    private enum CharResult {
        case correct     // Green: right char, right position
        case misplaced   // Yellow: right char, wrong position
        case wrong       // Gray: not in the idiom
    }

    // MARK: - Properties
    private var targetIdiom: String = ""
    private var guesses: [[String]] = []       // Each guess is 4 chars
    private var guessResults: [[CharResult]] = []
    private var currentGuess: [String] = []
    private var currentAttempt = 0
    private let maxAttempts = 6
    private var isGameOver = false
    private var gameWon = false

    /// All idioms (built-in + custom)
    private var idiomPool: [String] = []

    /// 49 candidate characters for this round (includes the 4 target chars + 45 distractors)
    private var candidateChars: [String] = []

    // MARK: - Subviews
    private let headerView = UIView()
    private let attemptLabel = UILabel()
    private let scoreLabel = UILabel()

    private let scrollView = UIScrollView()
    private let contentView = UIView()

    /// 6×4 grid of character labels for guesses
    private var guessGridLabels: [[UILabel]] = []

    /// Labels for the current guess being composed
    private var currentGuessLabels: [UILabel] = []

    /// Candidate character buttons (palette) — built in popup
    private var candidateButtons: [UIButton] = []

    /// Floating popup for candidate selection
    private var candidatePopupView: UIView?
    private var popupCardBottomConstraint: NSLayoutConstraint?
    private var popupCard: UIView?

    private let submitButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    private let gameOverView = UIView()
    private let gameOverTitleLabel = UILabel()
    private let gameOverScoreLabel = UILabel()
    private let restartButton = UIButton(type: .system)
    private let exitButton = UIButton(type: .system)

    // MARK: - Initialization
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startNewGame()
    }

    // MARK: - Game Logic
    private func buildIdiomPool() -> [String] {
        let builtIn = IdiomWordleViewController.builtInIdioms
        let custom = CustomIdiomManager.shared.customIdioms
        // Merge and deduplicate
        var all = builtIn
        for idiom in custom {
            if !all.contains(idiom) {
                all.append(idiom)
            }
        }
        return all
    }

    private func startNewGame() {
        // Build fresh pool (includes custom idioms)
        idiomPool = buildIdiomPool()
        
        // Pick random idiom
        targetIdiom = idiomPool.randomElement() ?? "一心一意"
        guesses.removeAll()
        guessResults.removeAll()
        currentGuess.removeAll()
        currentAttempt = 0
        isGameOver = false
        gameWon = false

        // Build candidate chars with distractor idioms for difficulty
        let targetChars = targetIdiom.map { String($0) }
        var pool = Set<String>(targetChars)

        // Find distractor idioms that share characters with target (confusing!)
        var distractorIdioms: [String] = []
        for idiom in idiomPool where idiom != targetIdiom {
            let idiomChars = Set(idiom.map { String($0) })
            let overlap = idiomChars.intersection(Set(targetChars))
            // Prefer idioms with 1-2 overlapping chars
            if overlap.count >= 1 && overlap.count <= 2 {
                distractorIdioms.append(idiom)
            }
        }

        // Pick up to 8 distractor idioms, add all their chars
        let selectedDistractors = distractorIdioms.shuffled().prefix(8)
        for idiom in selectedDistractors {
            for ch in idiom.map({ String($0) }) {
                pool.insert(ch)
            }
        }

        // Fill remaining slots with random chars from other idioms
        let allChars = idiomPool.joined().map { String($0) }
        let otherChars = Array(Set(allChars).subtracting(pool))
        let remaining = 49 - pool.count
        if remaining > 0 {
            pool.formUnion(otherChars.shuffled().prefix(remaining))
        }

        // Trim to exactly 49
        candidateChars = Array(pool).shuffled().prefix(49).map { $0 }

        // Reset UI
        resetGuessGrid()
        updateHeader()
        gameOverView.isHidden = true
    }

    // MARK: - Character Selection
    @objc private func candidateTapped(_ sender: UIButton) {
        guard !isGameOver, currentGuess.count < 4 else { return }
        let char = candidateChars[sender.tag]
        currentGuess.append(char)
        updateCurrentGuessDisplay()
    }

    @objc private func showCandidatePopup() {
        guard !isGameOver else { return }
        hideCandidatePopup()

        // Background overlay
        let popup = UIView()
        popup.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        popup.alpha = 0
        popup.translatesAutoresizingMaskIntoConstraints = false
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(dismissPopup))
        popup.addGestureRecognizer(dismissTap)
        view.addSubview(popup)
        candidatePopupView = popup

        // Card — initially off-screen below
        let card = UIView()
        card.backgroundColor = .cardBackground
        card.translatesAutoresizingMaskIntoConstraints = false
        card.isUserInteractionEnabled = true
        let cardTap = UITapGestureRecognizer(target: nil, action: nil)
        card.addGestureRecognizer(cardTap)
        popup.addSubview(card)
        popupCard = card

        // Handle bar
        let handleBar = UIView()
        handleBar.backgroundColor = .separator
        handleBar.layer.cornerRadius = 2.5
        handleBar.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(handleBar)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = "点击选字"
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .textSecondary
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        // 7×7 grid
        let paletteGrid = UIStackView()
        paletteGrid.axis = .vertical
        paletteGrid.spacing = 4
        paletteGrid.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(paletteGrid)

        candidateButtons.removeAll()
        for row in 0..<7 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 4
            rowStack.distribution = .fillEqually
            paletteGrid.addArrangedSubview(rowStack)

            for col in 0..<7 {
                let index = row * 7 + col
                let button = UIButton(type: .system)
                button.setTitle(index < candidateChars.count ? candidateChars[index] : "", for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                button.setTitleColor(.textPrimary, for: .normal)
                button.backgroundColor = .background
                button.layer.cornerRadius = 4
                button.layer.borderWidth = 1
                button.layer.borderColor = UIColor.separator.cgColor
                button.tag = index
                button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
                button.translatesAutoresizingMaskIntoConstraints = false
                button.heightAnchor.constraint(equalToConstant: 36).isActive = true
                candidateButtons.append(button)
                rowStack.addArrangedSubview(button)
            }
        }

        // Constrain card to bottom
        let cardBottom = card.bottomAnchor.constraint(equalTo: popup.bottomAnchor, constant: 500) // off-screen
        popupCardBottomConstraint = cardBottom

        NSLayoutConstraint.activate([
            popup.topAnchor.constraint(equalTo: view.topAnchor),
            popup.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            popup.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            popup.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            card.leadingAnchor.constraint(equalTo: popup.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: popup.trailingAnchor),
            cardBottom,

            handleBar.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            handleBar.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            handleBar.widthAnchor.constraint(equalToConstant: 36),
            handleBar.heightAnchor.constraint(equalToConstant: 5),

            titleLabel.topAnchor.constraint(equalTo: handleBar.bottomAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            paletteGrid.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            paletteGrid.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            paletteGrid.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            paletteGrid.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])

        // Apply top-only rounded corners (iOS 10 compatible)
        card.layoutIfNeeded()
        let maskPath = UIBezierPath(roundedRect: card.bounds,
                                     byRoundingCorners: [.topLeft, .topRight],
                                     cornerRadii: CGSize(width: 14, height: 14))
        let maskLayer = CAShapeLayer()
        maskLayer.path = maskPath.cgPath
        card.layer.mask = maskLayer

        // Animate in
        view.layoutIfNeeded()
        popupCardBottomConstraint?.constant = 0
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
            popup.alpha = 1
            self.view.layoutIfNeeded()
        })

        // Add pan to dismiss
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePopupPan(_:)))
        card.addGestureRecognizer(pan)
    }

    @objc private func handlePopupPan(_ gesture: UIPanGestureRecognizer) {
        guard let card = popupCard, let bottomConstraint = popupCardBottomConstraint else { return }
        let translation = gesture.translation(in: card)

        switch gesture.state {
        case .changed:
            if translation.y > 0 {
                bottomConstraint.constant = translation.y
            }
        case .ended, .cancelled:
            if translation.y > 100 {
                dismissPopup()
            } else {
                bottomConstraint.constant = 0
                UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
            }
        default:
            break
        }
    }

    @objc private func dismissPopup() {
        guard let popup = candidatePopupView, let bottomConstraint = popupCardBottomConstraint else { return }
        bottomConstraint.constant = 500
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseIn, animations: {
            popup.alpha = 0
            self.view.layoutIfNeeded()
        }) { _ in
            self.hideCandidatePopup()
        }
    }

    private func hideCandidatePopup() {
        candidatePopupView?.removeFromSuperview()
        candidatePopupView = nil
        popupCard = nil
        popupCardBottomConstraint = nil
    }

    @objc private func deleteTapped() {
        guard !isGameOver, !currentGuess.isEmpty else { return }
        currentGuess.removeLast()
        updateCurrentGuessDisplay()
    }

    @objc private func submitTapped() {
        guard !isGameOver, currentGuess.count == 4 else { return }

        let targetChars = targetIdiom.map { String($0) }
        var result: [CharResult] = Array(repeating: .wrong, count: 4)
        var remainingTarget = targetChars

        for i in 0..<4 {
            if currentGuess[i] == targetChars[i] {
                result[i] = .correct
                if let idx = remainingTarget.firstIndex(of: currentGuess[i]) {
                    remainingTarget.remove(at: idx)
                }
            }
        }
        for i in 0..<4 {
            if result[i] == .correct { continue }
            if let idx = remainingTarget.firstIndex(of: currentGuess[i]) {
                result[i] = .misplaced
                remainingTarget.remove(at: idx)
            }
        }

        guesses.append(currentGuess)
        guessResults.append(result)
        updateGuessGridRow(at: currentAttempt, chars: currentGuess, results: result)

        if currentGuess == targetChars {
            gameWon = true
            isGameOver = true
            endGame()
            return
        }

        currentAttempt += 1
        currentGuess.removeAll()
        updateCurrentGuessDisplay()
        updateHeader()

        if currentAttempt >= maxAttempts {
            isGameOver = true
            endGame()
        }
    }

    // MARK: - UI Updates
    private func resetGuessGrid() {
        for row in 0..<maxAttempts {
            for col in 0..<4 {
                guessGridLabels[row][col].text = ""
                guessGridLabels[row][col].backgroundColor = .clear
                guessGridLabels[row][col].textColor = .textPrimary
                guessGridLabels[row][col].layer.borderColor = UIColor.separator.cgColor
            }
        }
        currentGuess.removeAll()
        updateCurrentGuessDisplay()
    }

    private func updateGuessGridRow(at row: Int, chars: [String], results: [CharResult]) {
        for col in 0..<4 {
            let label = guessGridLabels[row][col]
            label.text = chars[col]
            switch results[col] {
            case .correct:
                label.backgroundColor = UIColor(red: 0.42, green: 0.67, blue: 0.28, alpha: 1.0)
                label.textColor = .white
                label.layer.borderColor = UIColor.clear.cgColor
            case .misplaced:
                label.backgroundColor = UIColor(red: 0.79, green: 0.63, blue: 0.16, alpha: 1.0)
                label.textColor = .white
                label.layer.borderColor = UIColor.clear.cgColor
            case .wrong:
                label.backgroundColor = UIColor(white: 0.5, alpha: 1.0)
                label.textColor = .white
                label.layer.borderColor = UIColor.clear.cgColor
            }
        }
    }

    private func updateCurrentGuessDisplay() {
        for i in 0..<4 {
            if i < currentGuess.count {
                currentGuessLabels[i].text = currentGuess[i]
                currentGuessLabels[i].textColor = .textPrimary
            } else {
                currentGuessLabels[i].text = ""
            }
            currentGuessLabels[i].backgroundColor = .clear
            currentGuessLabels[i].layer.borderColor = UIColor.separator.cgColor
        }
        if currentGuess.count < 4 && !isGameOver {
            let active = currentGuessLabels[currentGuess.count]
            active.layer.borderColor = UIColor.primary.cgColor
            active.layer.borderWidth = 2
        }
    }

    private func updateHeader() {
        attemptLabel.text = "第 \(currentAttempt + 1)/\(maxAttempts) 次猜测"
        scoreLabel.text = "目标：四字成语"
    }

    private func endGame() {
        let costCoins = DeveloperSettingsManager.shared.effectiveIdiomWordleCostCoins

        if gameWon {
            let rewardCoins = costCoins * 2
            RewardManager.shared.coins += rewardCoins

            let attemptsUsed = currentAttempt + 1
            let stars: String
            switch attemptsUsed {
            case 1: stars = "⭐⭐⭐⭐⭐"
            case 2: stars = "⭐⭐⭐⭐"
            case 3: stars = "⭐⭐⭐"
            case 4: stars = "⭐⭐"
            default: stars = "⭐"
            }

            gameOverTitleLabel.text = "🎉 猜对了！"
            gameOverScoreLabel.text = "成语：\(targetIdiom)\n用了 \(attemptsUsed) 次猜测 \(stars)\n获得金币：\(rewardCoins)💰"
        } else {
            gameOverTitleLabel.text = "😔 没猜出来"
            gameOverScoreLabel.text = "答案是：\(targetIdiom)\n再接再厉！"
        }

        gameOverView.isHidden = false
    }

    // MARK: - Actions
    @objc private func restartTapped() {
        let costCoins = DeveloperSettingsManager.shared.effectiveIdiomWordleCostCoins
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
        startNewGame()
    }

    @objc private func exitTapped() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "成语猜猜乐"
        navigationItem.hidesBackButton = true

        // Header
        headerView.backgroundColor = .cardBackground
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        attemptLabel.font = UIFont.systemFont(ofSize: 14)
        attemptLabel.textColor = .textSecondary
        attemptLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(attemptLabel)

        scoreLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        scoreLabel.textColor = .primary
        scoreLabel.textAlignment = .right
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(scoreLabel)

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        // ===== CURRENT GUESS ROW (top) =====
        let currentRowLabel = UILabel()
        currentRowLabel.text = "当前输入："
        currentRowLabel.font = UIFont.systemFont(ofSize: 13)
        currentRowLabel.textColor = .textTertiary
        currentRowLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(currentRowLabel)

        let currentRowStack = UIStackView()
        currentRowStack.axis = .horizontal
        currentRowStack.spacing = 6
        currentRowStack.distribution = .fillEqually
        currentRowStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(currentRowStack)

        for _ in 0..<4 {
            let label = UILabel()
            label.text = ""
            label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
            label.textColor = .textPrimary
            label.textAlignment = .center
            label.layer.cornerRadius = 5
            label.layer.borderWidth = 2
            label.layer.borderColor = UIColor.separator.cgColor
            label.clipsToBounds = true
            label.translatesAutoresizingMaskIntoConstraints = false
            label.heightAnchor.constraint(equalToConstant: 38).isActive = true
            currentGuessLabels.append(label)
            currentRowStack.addArrangedSubview(label)
        }

        // Delete + Submit buttons
        deleteButton.setTitle("⌫ 删除", for: .normal)
        deleteButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        deleteButton.setTitleColor(.textSecondary, for: .normal)
        deleteButton.backgroundColor = .separator
        deleteButton.layer.cornerRadius = 6
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(deleteButton)

        submitButton.setTitle("提交", for: .normal)
        submitButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        submitButton.backgroundColor = .primary
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.layer.cornerRadius = 6
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submitButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(submitButton)

        // ===== COLOR LEGEND =====
        let legendView = UIStackView()
        legendView.axis = .horizontal
        legendView.spacing = 16
        legendView.alignment = .center
        legendView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(legendView)

        let legendItems: [(color: UIColor, text: String)] = [
            (UIColor(red: 0.42, green: 0.67, blue: 0.28, alpha: 1.0), "字对位对"),
            (UIColor(red: 0.79, green: 0.63, blue: 0.16, alpha: 1.0), "字对位错"),
            (UIColor(white: 0.5, alpha: 1.0), "不在其中")
        ]
        for (color, text) in legendItems {
            let item = UIStackView()
            item.axis = .horizontal
            item.spacing = 4
            item.alignment = .center
            let box = UIView()
            box.backgroundColor = color
            box.layer.cornerRadius = 3
            box.translatesAutoresizingMaskIntoConstraints = false
            box.widthAnchor.constraint(equalToConstant: 12).isActive = true
            box.heightAnchor.constraint(equalToConstant: 12).isActive = true
            item.addArrangedSubview(box)
            let lbl = UILabel()
            lbl.text = text
            lbl.font = UIFont.systemFont(ofSize: 11)
            lbl.textColor = .textSecondary
            item.addArrangedSubview(lbl)
            legendView.addArrangedSubview(item)
        }

        // ===== GUESS GRID (history, below) =====
        let gridLabel = UILabel()
        gridLabel.text = "猜测记录："
        gridLabel.font = UIFont.systemFont(ofSize: 13)
        gridLabel.textColor = .textTertiary
        gridLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(gridLabel)

        let gridContainer = UIStackView()
        gridContainer.axis = .vertical
        gridContainer.spacing = 6
        gridContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(gridContainer)

        for row in 0..<maxAttempts {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 6
            rowStack.distribution = .fillEqually
            gridContainer.addArrangedSubview(rowStack)

            var rowLabels: [UILabel] = []
            for _ in 0..<4 {
                let label = UILabel()
                label.text = ""
                label.font = UIFont.systemFont(ofSize: 22, weight: .bold)
                label.textColor = .textPrimary
                label.textAlignment = .center
                label.layer.cornerRadius = 5
                label.layer.borderWidth = 1.5
                label.layer.borderColor = UIColor.separator.cgColor
                label.clipsToBounds = true
                label.translatesAutoresizingMaskIntoConstraints = false
                label.heightAnchor.constraint(equalToConstant: 38).isActive = true
                rowLabels.append(label)
                rowStack.addArrangedSubview(label)
            }
            guessGridLabels.append(rowLabels)
        }

        // Tap gesture on current guess row to show candidate popup
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(showCandidatePopup))
        currentRowStack.addGestureRecognizer(tapGesture)
        currentRowStack.isUserInteractionEnabled = true

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
        gameOverScoreLabel.numberOfLines = 4
        gameOverScoreLabel.translatesAutoresizingMaskIntoConstraints = false
        goCard.addSubview(gameOverScoreLabel)

        let costCoinsLabel = DeveloperSettingsManager.shared.effectiveIdiomWordleCostCoins
        restartButton.setTitle("再来一局 (-\(costCoinsLabel)💰)", for: .normal)
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
            headerView.heightAnchor.constraint(equalToConstant: 44),

            attemptLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            attemptLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            scoreLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            scoreLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // ScrollView
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            // Current guess row (top)
            currentRowLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            currentRowLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            currentRowStack.topAnchor.constraint(equalTo: currentRowLabel.bottomAnchor, constant: 4),
            currentRowStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            currentRowStack.widthAnchor.constraint(equalToConstant: 232),

            deleteButton.topAnchor.constraint(equalTo: currentRowStack.bottomAnchor, constant: 8),
            deleteButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            deleteButton.widthAnchor.constraint(equalToConstant: 80),
            deleteButton.heightAnchor.constraint(equalToConstant: 36),

            submitButton.topAnchor.constraint(equalTo: currentRowStack.bottomAnchor, constant: 8),
            submitButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            submitButton.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 12),
            submitButton.heightAnchor.constraint(equalToConstant: 36),

            // Legend
            legendView.topAnchor.constraint(equalTo: deleteButton.bottomAnchor, constant: 14),
            legendView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            // Guess grid (history, below)
            gridLabel.topAnchor.constraint(equalTo: legendView.bottomAnchor, constant: 10),
            gridLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            gridContainer.topAnchor.constraint(equalTo: gridLabel.bottomAnchor, constant: 4),
            gridContainer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            gridContainer.widthAnchor.constraint(equalToConstant: 232),
            gridContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            // Game over
            gameOverView.topAnchor.constraint(equalTo: view.topAnchor),
            gameOverView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gameOverView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gameOverView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            goCard.centerXAnchor.constraint(equalTo: gameOverView.centerXAnchor),
            goCard.centerYAnchor.constraint(equalTo: gameOverView.centerYAnchor),
            goCard.widthAnchor.constraint(equalToConstant: 280),
            goCard.heightAnchor.constraint(equalToConstant: 260),

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

    // MARK: - Built-in Idiom Dictionary (200 idioms)
    static let builtInIdioms: [String] = [
        "一心一意", "三心二意", "四面八方", "五颜六色", "七上八下",
        "九牛一毛", "十全十美", "百发百中", "千变万化", "万无一失",
        "天长地久", "风调雨顺", "国泰民安", "春暖花开", "秋高气爽",
        "山清水秀", "鸟语花香", "风和日丽", "花好月圆", "人山人海",
        "车水马龙", "自由自在", "无忧无虑", "自言自语", "不慌不忙",
        "不知不觉", "大公无私", "大器晚成", "大智若愚", "心平气和",
        "心想事成", "心花怒放", "一帆风顺", "一鸣惊人", "一举两得",
        "马到成功", "龙飞凤舞", "虎头蛇尾", "画蛇添足", "对牛弹琴",
        "守株待兔", "亡羊补牢", "井底之蛙", "狐假虎威", "叶公好龙",
        "刻舟求剑", "掩耳盗铃", "学以致用", "温故知新", "举一反三",
        "雪中送炭", "锦上添花", "落井下石", "火上浇油", "水落石出",
        "惊天动地", "开天辟地", "顶天立地", "欢天喜地", "冰天雪地",
        "披星戴月", "如鱼得水", "如虎添翼", "如胶似漆", "如雷贯耳",
        "指鹿为马", "点石成金", "抛砖引玉", "杀鸡儆猴", "打草惊蛇",
        "调虎离山", "声东击西", "暗度陈仓", "隔岸观火", "笑里藏刀",
        "借刀杀人", "趁火打劫", "浑水摸鱼", "金蝉脱壳", "关门捉贼",
        "远交近攻", "假道伐虢", "偷梁换柱", "指桑骂槐", "假痴不癫",
        "上屋抽梯", "树上开花", "反客为主", "美人离间", "空城妙计",
        "反戈一击", "四面楚歌", "破釜沉舟", "背水一战", "卧薪尝胆",
        "纸上谈兵", "完璧归赵", "负荆请罪", "毛遂自荐", "脱颖而出",
        "胸有成竹", "入木三分", "炉火纯青", "游刃有余", "得心应手",
        "目无全牛", "庖丁解牛", "班门弄斧", "邯郸学步", "东施效颦",
        "爱屋及乌", "按图索骥", "百折不挠", "半途而废", "包罗万象",
        "别出心裁", "波涛汹涌", "博古通今", "不耻下问", "不屈不挠",
        "沧海桑田", "草木皆兵", "姹紫嫣红", "畅所欲言", "朝三暮四",
        "程门立雪", "叱咤风云", "出类拔萃", "触类旁通", "川流不息",
        "垂头丧气", "唇亡齿寒", "从容不迫", "寸步不离", "措手不及",
        "大刀阔斧", "大义灭亲", "胆大包天", "当机立断", "道听途说",
        "得陇望蜀", "滴水穿石", "东山再起", "独具匠心", "多多益善",
        "耳濡目染", "发愤图强", "翻山越岭", "废寝忘食", "奋不顾身",
        "丰功伟绩", "风和日暖", "负隅顽抗", "赴汤蹈火", "高瞻远瞩",
        "各抒己见", "功亏一篑", "孤注一掷", "刮目相看", "海阔天空",
        "含辛茹苦", "和衷共济", "鹤立鸡群", "后来居上", "虎视眈眈",
        "华而不实", "患难与共", "挥金如土", "集思广益", "既往不咎",
        "坚持不懈", "坚韧不拔", "见义勇为", "脚踏实地", "竭尽全力",
        "精益求精", "居安思危", "举足轻重", "聚精会神", "开卷有益",
        "慷慨激昂", "刻不容缓", "苦尽甘来", "滥竽充数", "老当益壮",
        "理直气壮", "力挽狂澜", "两全其美", "柳暗花明", "满载而归",
        "茅塞顿开", "妙手回春", "名不虚传", "名列前茅", "明察秋毫",
        "摩拳擦掌", "目不暇接", "难以置信", "宁缺毋滥", "呕心沥血",
        "庞然大物", "披荆斩棘", "平易近人", "迫不及待", "七嘴八舌",
        "齐心协力", "千钧一发", "前车之鉴", "巧夺天工", "青出于蓝",
        "全力以赴", "忍辱负重", "任重道远", "融会贯通", "三顾茅庐",
        "舍己为人", "深入浅出", "生机勃勃", "史无前例", "事半功倍",
        "手不释卷", "首当其冲", "熟能生巧", "水到渠成", "死而后已",
        "随遇而安", "所向披靡", "谈笑风生", "提心吊胆", "天翻地覆",
        "铁杵成针", "通宵达旦", "推陈出新", "脱颖而出", "万象更新",
        "万紫千红", "微不足道", "闻鸡起舞", "我行我素", "无地自容",
        "无价之宝", "无可奈何", "无所畏惧", "无微不至", "相辅相成",
        "心旷神怡", "兴高采烈", "胸无点墨", "虚怀若谷", "栩栩如生",
        "悬崖勒马", "学富五车", "雪上加霜", "言简意赅", "眼高手低",
        "阳春白雪", "养精蓄锐", "摇摇欲坠", "一败涂地", "一成不变",
        "一帆风顺", "一鼓作气", "一箭双雕", "一诺千金", "一丝不苟",
        "异想天开", "抑扬顿挫", "迎刃而解", "永垂不朽", "勇往直前",
        "有口皆碑", "与日俱增", "语重心长", "源远流长", "越俎代庖",
        "再接再厉", "斩钉截铁", "张冠李戴", "朝气蓬勃", "真相大白",
        "争分夺秒", "知难而进", "纸上谈兵", "志同道合", "专心致志",
        "自告奋勇", "自力更生", "自相矛盾", "纵横交错", "左右逢源",
    ]
}
