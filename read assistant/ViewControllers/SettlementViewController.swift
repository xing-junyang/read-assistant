import UIKit

// MARK: - Settlement View Controller
/// Displays reading results and reward summary after completing a reading session.
/// Shows score, XP/coin gains, check-in rewards, and level-up celebrations.
final class SettlementViewController: UIViewController {

    // MARK: - Model
    struct SettlementData {
        let overallScore: Double
        let completedCount: Int
        let totalCount: Int
        let xpGained: Int
        let newLevel: Int
        let leveledUp: Bool
        let newTitle: LevelTitle
        let coinsGained: Int
        let checkInResult: RewardManager.CheckInRewardResult
        let totalXP: Int
        let totalCoins: Int
        let levelProgress: Double
        let onReread: () -> Void
        let onDismiss: () -> Void
    }

    private let data: SettlementData

    // MARK: - Subviews
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // MARK: - Initialization
    init(data: SettlementData) {
        self.data = data
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        playCompletionSound()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Animate elements sequentially
        animateEntrance()
    }

    // MARK: - Sound Effect
    private func playCompletionSound() {
        SoundEffectManager.shared.playCompletionSound()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "阅读结算"

        // Hide back button, use custom dismiss
        navigationItem.hidesBackButton = true

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        // Content Stack
        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.alpha = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: compatSafeAreaBottom),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        // Score section
        contentStack.addArrangedSubview(createScoreSection())

        // XP section
        contentStack.addArrangedSubview(createXPSection())

        // Coin section (only if coins gained)
        if data.coinsGained > 0 {
            contentStack.addArrangedSubview(createCoinSection())
        }

        // Check-in section (only if rewarded)
        if data.checkInResult.isRewarded {
            contentStack.addArrangedSubview(createCheckInSection())
        }

        // Level-up celebration (if leveled up)
        if data.leveledUp {
            contentStack.addArrangedSubview(createLevelUpSection())
        }

        // Buttons
        contentStack.addArrangedSubview(createButtonSection())
    }

    // MARK: - Section Builders

    private func createScoreSection() -> UIView {
        let card = createCard()

        let trophyLabel = UILabel()
        trophyLabel.text = scoreEmoji()
        trophyLabel.font = UIFont.systemFont(ofSize: 64)
        trophyLabel.textAlignment = .center
        trophyLabel.translatesAutoresizingMaskIntoConstraints = false

        let scoreLabel = UILabel()
        scoreLabel.text = "\(Int(data.overallScore))"
        scoreLabel.font = UIFont.systemFont(ofSize: 56, weight: .bold)
        scoreLabel.textColor = scoreColor()
        scoreLabel.textAlignment = .center
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false

        let percentLabel = UILabel()
        percentLabel.text = "分"
        percentLabel.font = UIFont.systemFont(ofSize: 20, weight: .medium)
        percentLabel.textColor = .textSecondary
        percentLabel.textAlignment = .center
        percentLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = data.totalCount > 0
            ? "共完成 \(data.completedCount)/\(data.totalCount) 段文本"
            : "暂无评分数据"
        descLabel.font = UIFont.systemFont(ofSize: 14)
        descLabel.textColor = .textSecondary
        descLabel.textAlignment = .center
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "🎉 阅读完成！"
        titleLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .textPrimary
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addArrangedSubview(titleLabel)
        card.addArrangedSubview(createSpacer(4))
        card.addArrangedSubview(trophyLabel)
        card.addArrangedSubview(scoreLabel)
        card.addArrangedSubview(percentLabel)
        card.addArrangedSubview(createSpacer(4))
        card.addArrangedSubview(descLabel)

        return card
    }

    private func createXPSection() -> UIView {
        let card = createCard()

        let headerLabel = UILabel()
        headerLabel.text = "⚡ 经验值"
        headerLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        headerLabel.textColor = .textPrimary
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        // XP gained row
        let gainedRow = createInfoRow(
            icon: "⬆️",
            label: "本次获得",
            value: "+\(data.xpGained) XP",
            valueColor: .successGreen
        )

        // Current level row
        let levelRow = createInfoRow(
            icon: data.newTitle.icon,
            label: "当前等级",
            value: "Lv.\(data.newLevel) \(data.newTitle.title)",
            valueColor: .primary
        )

        // Total XP row
        let totalRow = createInfoRow(
            icon: "📊",
            label: "累计经验",
            value: "\(data.totalXP) XP",
            valueColor: .textSecondary
        )

        // Progress bar
        let progressView = UIProgressView()
        progressView.progressTintColor = .accent
        progressView.trackTintColor = .separator
        progressView.progress = Float(data.levelProgress)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.layer.cornerRadius = 3
        progressView.clipsToBounds = true
        progressView.transform = CGAffineTransform(scaleX: 1, y: 1.5)

        let progressLabel = UILabel()
        progressLabel.text = "距下一级 \(Int((1 - data.levelProgress) * 100))%"
        progressLabel.font = UIFont.systemFont(ofSize: 11)
        progressLabel.textColor = .textTertiary
        progressLabel.textAlignment = .right
        progressLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addArrangedSubview(headerLabel)
        card.addArrangedSubview(gainedRow)
        card.addArrangedSubview(createSeparator())
        card.addArrangedSubview(levelRow)
        card.addArrangedSubview(createSeparator())
        card.addArrangedSubview(totalRow)
        card.addArrangedSubview(createSpacer(4))
        card.addArrangedSubview(progressView)
        card.addArrangedSubview(progressLabel)

        return card
    }

    private func createCoinSection() -> UIView {
        let card = createCard()

        let headerLabel = UILabel()
        headerLabel.text = "💰 金币"
        headerLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        headerLabel.textColor = .textPrimary
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        let gainedRow = createInfoRow(
            icon: "⬆️",
            label: "本次获得",
            value: "+\(data.coinsGained) 💰",
            valueColor: .accent
        )

        let totalRow = createInfoRow(
            icon: "💰",
            label: "当前金币",
            value: "💰 \(data.totalCoins)",
            valueColor: .textSecondary
        )

        card.addArrangedSubview(headerLabel)
        card.addArrangedSubview(gainedRow)
        card.addArrangedSubview(createSeparator())
        card.addArrangedSubview(totalRow)

        return card
    }

    private func createCheckInSection() -> UIView {
        let card = createCard()

        let headerLabel = UILabel()
        headerLabel.text = "📅 签到奖励"
        headerLabel.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        headerLabel.textColor = .textPrimary
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        var rewardName = ""
        switch data.checkInResult {
        case .day3(let name):
            rewardName = "🎁 \(name)（连续签到3天）"
        case .day7(let name):
            rewardName = "🎁 \(name)（连续签到7天）"
        case .none:
            break
        }

        let rewardLabel = UILabel()
        rewardLabel.text = rewardName
        rewardLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        rewardLabel.textColor = .successGreen
        rewardLabel.numberOfLines = 0
        rewardLabel.translatesAutoresizingMaskIntoConstraints = false

        let hintLabel = UILabel()
        hintLabel.text = "已放入库存，可前往奖励页查看"
        hintLabel.font = UIFont.systemFont(ofSize: 12)
        hintLabel.textColor = .textTertiary
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addArrangedSubview(headerLabel)
        card.addArrangedSubview(rewardLabel)
        card.addArrangedSubview(hintLabel)

        return card
    }

    private func createLevelUpSection() -> UIView {
        let card = createCard()
        card.backgroundColor = UIColor.accent.withAlphaComponent(0.08)
        card.layer.borderWidth = 2
        card.layer.borderColor = UIColor.accent.cgColor

        let celebrationLabel = UILabel()
        celebrationLabel.text = "🎊 升级啦！"
        celebrationLabel.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        celebrationLabel.textColor = .accent
        celebrationLabel.textAlignment = .center
        celebrationLabel.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "\(data.newTitle.icon) \(data.newTitle.title)"
        titleLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .textPrimary
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let levelLabel = UILabel()
        levelLabel.text = "Lv.\(data.newLevel)"
        levelLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        levelLabel.textColor = .textSecondary
        levelLabel.textAlignment = .center
        levelLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addArrangedSubview(celebrationLabel)
        card.addArrangedSubview(titleLabel)
        card.addArrangedSubview(levelLabel)

        return card
    }

    private func createButtonSection() -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12

        // Reread button
        let rereadButton = UIButton(type: .system)
        rereadButton.setTitle("🔄 重新阅读", for: .normal)
        rereadButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        rereadButton.setTitleColor(.white, for: .normal)
        rereadButton.backgroundColor = .primary
        rereadButton.layer.cornerRadius = 12
        rereadButton.addTarget(self, action: #selector(rereadTapped), for: .touchUpInside)
        rereadButton.translatesAutoresizingMaskIntoConstraints = false
        rereadButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        container.addArrangedSubview(rereadButton)

        // Back button
        let backButton = UIButton(type: .system)
        backButton.setTitle("返回首页", for: .normal)
        backButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        backButton.setTitleColor(.primary, for: .normal)
        backButton.backgroundColor = .cardBackground
        backButton.layer.cornerRadius = 12
        backButton.layer.borderWidth = 1
        backButton.layer.borderColor = UIColor.primary.cgColor
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        container.addArrangedSubview(backButton)

        return container
    }

    // MARK: - Helpers

    private func createCard() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.backgroundColor = .cardBackground
        stack.layer.cornerRadius = 12
        stack.layer.shadowColor = UIColor.black.cgColor
        stack.layer.shadowOpacity = 0.05
        stack.layer.shadowOffset = CGSize(width: 0, height: 2)
        stack.layer.shadowRadius = 4
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func createSpacer(_ height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func createSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return view
    }

    private func createInfoRow(icon: String, label: String, value: String, valueColor: UIColor) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconLabel = UILabel()
        iconLabel.text = icon
        iconLabel.font = UIFont.systemFont(ofSize: 16)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.font = UIFont.systemFont(ofSize: 14)
        nameLabel.textColor = .textSecondary
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = valueColor
        valueLabel.textAlignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconLabel)
        container.addSubview(nameLabel)
        container.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),

            iconLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            iconLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 4),
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8)
        ])

        return container
    }

    // MARK: - Score Helpers

    private func scoreEmoji() -> String {
        if data.overallScore >= 95 { return "🏆" }
        if data.overallScore >= 90 { return "🌟" }
        if data.overallScore >= 80 { return "👍" }
        if data.overallScore >= 60 { return "📖" }
        return "💪"
    }

    private func scoreColor() -> UIColor {
        if data.overallScore >= 95 { return .accent }
        if data.overallScore >= 80 { return .successGreen }
        if data.overallScore >= 60 { return .primary }
        return .warningOrange
    }

    // MARK: - Animation

    private func animateEntrance() {
        UIView.animate(withDuration: 0.4, delay: 0.1, options: .curveEaseOut, animations: {
            self.contentStack.alpha = 1
        })
    }

    // MARK: - Actions

    @objc private func rereadTapped() {
        navigationController?.popViewController(animated: true)
        data.onReread()
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
        data.onDismiss()
    }
}
