import UIKit

// MARK: - Character Match View Controller
/// Classic memory card matching game: flip two cards to match Chinese characters
/// with their pinyin. Cards are drawn from wrong answer book items.
/// 4×3 grid = 12 cards (6 pairs). Costs 20 coins per play.
final class CharacterMatchViewController: UIViewController {

    // MARK: - Card Model
    private struct Card {
        let id: Int
        let content: String       // Displayed text (character or pinyin)
        let pairID: Int           // Shared ID for matching pairs
        let isCharacter: Bool     // true = character card, false = pinyin card
        var isFlipped: Bool = false
        var isMatched: Bool = false
    }

    // MARK: - Properties
    private var cards: [Card] = []
    private var cardButtons: [UIButton] = []
    private var firstSelectedIndex: Int? = nil
    private var flipCount = 0
    private var matchCount = 0
    private let totalPairs = 6
    private var isProcessing = false
    private var isGameOver = false

    private let gridColumns = 4
    private let gridRows = 3

    // MARK: - Subviews
    private let headerView = UIView()
    private let flipCountLabel = UILabel()
    private let matchCountLabel = UILabel()
    private let scoreLabel = UILabel()

    private let gridView = UIView()
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
        setupCards()
        layoutGrid()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    // MARK: - Card Setup
    private func setupCards() {
        // Get words from wrong answer book
        let wrongAnswers = WrongAnswerBookManager.shared.wrongAnswers
        var wordPool: [(character: String, pinyin: String)] = []

        for item in wrongAnswers {
            let text = item.correctText.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.count <= 3 else { continue }
            // Only CJK text
            guard text.unicodeScalars.allSatisfy({
                ($0.value >= 0x4E00 && $0.value <= 0x9FFF) || ($0.value >= 0x3400 && $0.value <= 0x4DBF)
            }) else { continue }

            let pinyin = pinyinOf(text)
            guard !pinyin.isEmpty, pinyin != text.lowercased() else { continue }
            wordPool.append((character: text, pinyin: pinyin))
        }

        // Shuffle and pick up to 6 pairs
        wordPool.shuffle()
        let selected = Array(wordPool.prefix(totalPairs))

        // Build cards
        var cardID = 0
        cards.removeAll()
        for (index, pair) in selected.enumerated() {
            cards.append(Card(id: cardID, content: pair.character, pairID: index, isCharacter: true))
            cardID += 1
            cards.append(Card(id: cardID, content: pair.pinyin, pairID: index, isCharacter: false))
            cardID += 1
        }

        cards.shuffle()
        flipCount = 0
        matchCount = 0
        isGameOver = false
        updateHeader()
    }

    /// Convert Chinese text to pinyin using CFStringTransform.
    private func pinyinOf(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        return (mutable as String).lowercased().replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Game Logic
    @objc private func cardTapped(_ sender: UIButton) {
        let index = sender.tag
        guard !isProcessing, !isGameOver,
              index < cards.count,
              !cards[index].isMatched,
              !cards[index].isFlipped else { return }

        // Flip card
        cards[index].isFlipped = true
        flipCount += 1
        updateCardButton(cardButtons[index], with: cards[index])
        updateHeader()

        if let firstIndex = firstSelectedIndex {
            // Second card selected
            isProcessing = true
            firstSelectedIndex = nil

            let firstCard = cards[firstIndex]
            let secondCard = cards[index]

            if firstCard.pairID == secondCard.pairID && firstCard.isCharacter != secondCard.isCharacter {
                // Match!
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    self.cards[firstIndex].isMatched = true
                    self.cards[index].isMatched = true
                    self.matchCount += 1
                    self.highlightMatch(self.cardButtons[firstIndex])
                    self.highlightMatch(self.cardButtons[index])
                    self.updateHeader()
                    self.isProcessing = false

                    // Check win
                    if self.matchCount >= self.totalPairs {
                        self.endGame()
                    }
                }
            } else {
                // No match - flip back after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                    guard let self = self else { return }
                    self.cards[firstIndex].isFlipped = false
                    self.cards[index].isFlipped = false
                    self.updateCardButton(self.cardButtons[firstIndex], with: self.cards[firstIndex])
                    self.updateCardButton(self.cardButtons[index], with: self.cards[index])
                    self.isProcessing = false
                }
            }
        } else {
            // First card selected
            firstSelectedIndex = index
        }
    }

    private func endGame() {
        isGameOver = true

        // Calculate score based on efficiency
        let efficiency = Double(totalPairs * 2) / Double(max(flipCount, 1))
        let score: Int
        if matchCount >= totalPairs {
            if flipCount <= totalPairs * 2 + 2 {
                score = 100  // Perfect or near-perfect
            } else if flipCount <= totalPairs * 3 {
                score = 80
            } else if flipCount <= totalPairs * 4 {
                score = 60
            } else {
                score = 40
            }
        } else {
            score = 0
        }

        // Rewards: 2x cost on full success
        let costCoins = DeveloperSettingsManager.shared.effectiveCharacterMatchCostCoins
        let rewardCoins: Int
        if score >= 80 {
            rewardCoins = costCoins * 2  // 2x cost
        } else if score >= 60 {
            rewardCoins = costCoins
        } else if score >= 40 {
            rewardCoins = costCoins / 2
        } else {
            rewardCoins = 0
        }

        if rewardCoins > 0 {
            RewardManager.shared.coins += rewardCoins
        }

        gameOverTitleLabel.text = matchCount >= totalPairs ? "🎉 全部配对成功！" : "游戏结束"
        gameOverScoreLabel.text = "翻牌次数：\(flipCount) 次\n配对成功：\(matchCount)/\(totalPairs) 对\n得分：\(score) 分\n获得金币：\(rewardCoins)💰"
        gameOverView.isHidden = false
    }

    private func highlightMatch(_ button: UIButton) {
        UIView.animate(withDuration: 0.3, animations: {
            button.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
        }) { _ in
            UIView.animate(withDuration: 0.3) {
                button.transform = .identity
            }
        }
    }

    // MARK: - UI Updates
    private func updateHeader() {
        flipCountLabel.text = "🔄 \(flipCount) 次"
        matchCountLabel.text = "✅ \(matchCount)/\(totalPairs)"

        let efficiency = Double(totalPairs * 2) / Double(max(flipCount, 1))
        let currentScore: Int
        if matchCount > 0 {
            currentScore = Int(efficiency * 50.0 * Double(matchCount) / Double(totalPairs))
        } else {
            currentScore = 0
        }
        scoreLabel.text = "⭐️ \(currentScore) 分"
    }

    private func updateCardButton(_ button: UIButton, with card: Card) {
        if card.isMatched {
            button.backgroundColor = .successGreen.withAlphaComponent(0.3)
            button.setTitle("", for: .normal)
            button.layer.borderColor = UIColor.successGreen.cgColor
            button.isUserInteractionEnabled = false
        } else if card.isFlipped {
            button.backgroundColor = .cardBackground
            if card.isCharacter {
                button.setTitle(card.content, for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .bold)
                button.setTitleColor(.textPrimary, for: .normal)
            } else {
                button.setTitle(card.content, for: .normal)
                button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
                button.setTitleColor(.primary, for: .normal)
            }
            button.layer.borderColor = UIColor.primary.cgColor
        } else {
            button.backgroundColor = .primary
            button.setTitle("?", for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .bold)
            button.setTitleColor(.white, for: .normal)
            button.layer.borderColor = UIColor.primaryDark.cgColor
        }
    }

    // MARK: - Actions
    @objc private func restartTapped() {
        // Check if user has enough coins
        let costCoins = DeveloperSettingsManager.shared.effectiveCharacterMatchCostCoins
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
        cardButtons.forEach { $0.removeFromSuperview() }
        cardButtons.removeAll()
        setupCards()
        layoutGrid()
    }

    @objc private func exitTapped() {
        navigationController?.popViewController(animated: true)
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "汉字消消乐"
        navigationItem.hidesBackButton = true

        // Header
        headerView.backgroundColor = .cardBackground
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        flipCountLabel.font = UIFont.systemFont(ofSize: 14)
        flipCountLabel.textColor = .textSecondary
        flipCountLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(flipCountLabel)

        matchCountLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        matchCountLabel.textColor = .successGreen
        matchCountLabel.textAlignment = .center
        matchCountLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(matchCountLabel)

        scoreLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        scoreLabel.textColor = .accent
        scoreLabel.textAlignment = .right
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(scoreLabel)

        // Grid container
        gridView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gridView)

        // Game over overlay
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

        let costCoinsLabel = DeveloperSettingsManager.shared.effectiveCharacterMatchCostCoins
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

        // Layout
        NSLayoutConstraint.activate([
            // Header
            headerView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50),

            flipCountLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            flipCountLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            matchCountLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            matchCountLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            scoreLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            scoreLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            // Grid
            gridView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 24),
            gridView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            gridView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            gridView.heightAnchor.constraint(equalTo: gridView.widthAnchor, multiplier: 0.75),

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

    private func layoutGrid() {
        // Remove old buttons
        cardButtons.forEach { $0.removeFromSuperview() }
        cardButtons.removeAll()

        let spacing: CGFloat = 8
        let totalSpacing = spacing * CGFloat(gridColumns - 1)
        let cardWidth = (gridView.bounds.width > 0 ? gridView.bounds.width : UIScreen.main.bounds.width - 32) - totalSpacing
        let cellWidth = cardWidth / CGFloat(gridColumns)
        let cellHeight = cellWidth  // Square cards

        for row in 0..<gridRows {
            for col in 0..<gridColumns {
                let index = row * gridColumns + col
                guard index < cards.count else { continue }

                let button = UIButton(type: .system)
                button.tag = index
                button.layer.cornerRadius = 8
                button.layer.borderWidth = 2
                button.addTarget(self, action: #selector(cardTapped(_:)), for: .touchUpInside)
                button.translatesAutoresizingMaskIntoConstraints = false
                gridView.addSubview(button)

                let xOffset = CGFloat(col) * (cellWidth + spacing)
                let yOffset = CGFloat(row) * (cellHeight + spacing)

                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: gridView.leadingAnchor, constant: xOffset),
                    button.topAnchor.constraint(equalTo: gridView.topAnchor, constant: yOffset),
                    button.widthAnchor.constraint(equalToConstant: cellWidth),
                    button.heightAnchor.constraint(equalToConstant: cellHeight)
                ])

                updateCardButton(button, with: cards[index])
                cardButtons.append(button)
            }
        }

        // Update grid height constraint
        let gridHeight = CGFloat(gridRows) * cellHeight + spacing * CGFloat(gridRows - 1)
        gridView.constraints.forEach { c in
            if c.firstAttribute == .height {
                c.isActive = false
            }
        }
        gridView.heightAnchor.constraint(equalToConstant: gridHeight + 20).isActive = true
    }
}
