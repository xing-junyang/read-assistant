import UIKit

// MARK: - Rewards View Controller
/// Main rewards tab showing XP/Level, Coin Shop, Check-in, and Inventory.
final class RewardsViewController: UIViewController {

    // MARK: - Properties
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    // XP/Level views
    private let levelLabel = UILabel()
    private let titleLabel = UILabel()
    private let xpProgressView = UIProgressView()
    private let xpDetailLabel = UILabel()

    // Coins views
    private let coinsLabel = UILabel()

    // Check-in views
    private let streakLabel = UILabel()
    private let weekStack = UIStackView()

    // Inventory views
    private let inventoryStack = UIStackView()

    // Shop views
    private let shopStack = UIStackView()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshAll()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "奖励"

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        // Content Stack
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: compatSafeAreaBottom),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        // Build sections
        contentStack.addArrangedSubview(createXPSection())
        contentStack.addArrangedSubview(createCoinsSection())
        contentStack.addArrangedSubview(createCheckInSection())
        contentStack.addArrangedSubview(createShopSection())
        contentStack.addArrangedSubview(createInventorySection())
    }

    // MARK: - Section Builders

    private func createXPSection() -> UIView {
        let card = createCard()

        // Header
        let header = createSectionHeader(title: "经验值", icon: "⚡")

        // Level circle
        levelLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        levelLabel.textColor = .primary
        levelLabel.textAlignment = .center
        levelLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.systemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = .accent
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        xpProgressView.progressTintColor = .accent
        xpProgressView.trackTintColor = .separator
        xpProgressView.translatesAutoresizingMaskIntoConstraints = false
        xpProgressView.layer.cornerRadius = 4
        xpProgressView.clipsToBounds = true
        xpProgressView.transform = CGAffineTransform(scaleX: 1, y: 2)

        xpDetailLabel.font = UIFont.systemFont(ofSize: 12)
        xpDetailLabel.textColor = .textSecondary
        xpDetailLabel.textAlignment = .center
        xpDetailLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addArrangedSubview(header)
        card.addArrangedSubview(levelLabel)
        card.addArrangedSubview(titleLabel)
        card.addArrangedSubview(createSpacer(8))
        card.addArrangedSubview(xpProgressView)
        card.addArrangedSubview(createSpacer(4))
        card.addArrangedSubview(xpDetailLabel)

        return card
    }

    private func createCoinsSection() -> UIView {
        let card = createCard()

        let header = createSectionHeader(title: "金币", icon: "💰")

        coinsLabel.font = UIFont.systemFont(ofSize: 36, weight: .bold)
        coinsLabel.textColor = .accent
        coinsLabel.textAlignment = .center
        coinsLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = "阅读分数 ≥ 80 分可获得金币"
        descLabel.font = UIFont.systemFont(ofSize: 12)
        descLabel.textColor = .textTertiary
        descLabel.textAlignment = .center
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addArrangedSubview(header)
        card.addArrangedSubview(coinsLabel)
        card.addArrangedSubview(descLabel)

        return card
    }

    private func createCheckInSection() -> UIView {
        let card = createCard()

        let header = createSectionHeader(title: "签到", icon: "📅")

        streakLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        streakLabel.textColor = .textPrimary
        streakLabel.textAlignment = .center
        streakLabel.numberOfLines = 0
        streakLabel.translatesAutoresizingMaskIntoConstraints = false

        // Week calendar
        weekStack.axis = .horizontal
        weekStack.spacing = 6
        weekStack.distribution = .fillEqually
        weekStack.alignment = .fill
        weekStack.translatesAutoresizingMaskIntoConstraints = false

        let rewardHint = UILabel()
        rewardHint.text = "连续签到 3 天：🎁 看一集动画片\n连续签到 7 天：🎁 周末去游乐园"
        rewardHint.font = UIFont.systemFont(ofSize: 12)
        rewardHint.textColor = .textTertiary
        rewardHint.numberOfLines = 0
        rewardHint.textAlignment = .center
        rewardHint.translatesAutoresizingMaskIntoConstraints = false

        card.addArrangedSubview(header)
        card.addArrangedSubview(streakLabel)
        card.addArrangedSubview(createSpacer(8))
        card.addArrangedSubview(weekStack)
        card.addArrangedSubview(createSpacer(4))
        card.addArrangedSubview(rewardHint)

        return card
    }

    private func createShopSection() -> UIView {
        let card = createCard()

        let header = createSectionHeader(title: "商店", icon: "🏬")

        shopStack.axis = .vertical
        shopStack.spacing = 0
        shopStack.translatesAutoresizingMaskIntoConstraints = false

        card.addArrangedSubview(header)
        card.addArrangedSubview(shopStack)

        return card
    }

    private func createInventorySection() -> UIView {
        let card = createCard()

        let header = createSectionHeader(title: "库存", icon: "🎒")

        inventoryStack.axis = .vertical
        inventoryStack.spacing = 0
        inventoryStack.translatesAutoresizingMaskIntoConstraints = false

        let emptyLabel = UILabel()
        emptyLabel.text = "暂无物品，去商店购买或签到获取吧！"
        emptyLabel.font = UIFont.systemFont(ofSize: 13)
        emptyLabel.textColor = .textTertiary
        emptyLabel.textAlignment = .center
        emptyLabel.tag = 999 // tag to find later
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        inventoryStack.addArrangedSubview(emptyLabel)

        card.addArrangedSubview(header)
        card.addArrangedSubview(inventoryStack)

        return card
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

    private func createSectionHeader(title: String, icon: String) -> UILabel {
        let label = UILabel()
        label.text = "\(icon)  \(title)"
        label.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        label.textColor = .textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func createSpacer(_ height: CGFloat) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    // MARK: - Refresh

    private func refreshAll() {
        refreshXP()
        refreshCoins()
        refreshCheckIn()
        refreshShop()
        refreshInventory()
    }

    private func refreshXP() {
        let manager = RewardManager.shared
        levelLabel.text = "Lv.\(manager.currentLevel)"
        titleLabel.text = "\(manager.currentTitle.icon) \(manager.currentTitle.title)"

        let progress = Float(manager.levelProgress)
        xpProgressView.progress = progress

        let currentLevelXP = LevelTitle.xpForLevel(manager.currentLevel)
        let nextLevel = min(manager.currentLevel + 1, 99)
        let nextLevelXP = LevelTitle.xpForLevel(nextLevel)
        let xpInLevel = manager.totalXP - currentLevelXP
        let xpNeeded = nextLevelXP - currentLevelXP
        xpDetailLabel.text = "\(xpInLevel) / \(xpNeeded) XP  ·  总经验 \(manager.totalXP)"
    }

    private func refreshCoins() {
        let manager = RewardManager.shared
        coinsLabel.text = "💰 \(manager.coins)"
    }

    private func refreshCheckIn() {
        let manager = RewardManager.shared
        let streak = manager.currentStreak()
        streakLabel.text = "已连续签到 \(streak) 天 🔥"

        // Rebuild week calendar
        weekStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let weekData = manager.weeklyCheckInStatus()
        let today = Calendar.current.startOfDay(for: Date())

        for (date, dayName, hasReading) in weekData {
            let dayView = createDayView(
                dayName: dayName,
                dayNumber: Calendar.current.component(.day, from: date),
                hasReading: hasReading,
                isToday: Calendar.current.isDate(date, inSameDayAs: today)
            )
            weekStack.addArrangedSubview(dayView)
        }
    }

    private func createDayView(dayName: String, dayNumber: Int, hasReading: Bool, isToday: Bool) -> UIView {
        let container = UIView()
        container.layer.cornerRadius = 8
        container.backgroundColor = hasReading ? .primaryLight : (isToday ? .accentLight.withAlphaComponent(0.3) : .background)
        container.layer.borderWidth = isToday ? 1.5 : 0
        container.layer.borderColor = isToday ? UIColor.accent.cgColor : UIColor.clear.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let dayLabel = UILabel()
        dayLabel.text = dayName
        dayLabel.font = UIFont.systemFont(ofSize: 11)
        dayLabel.textColor = .textSecondary
        dayLabel.textAlignment = .center
        dayLabel.translatesAutoresizingMaskIntoConstraints = false

        let numLabel = UILabel()
        numLabel.text = "\(dayNumber)"
        numLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        numLabel.textColor = hasReading ? .white : .textPrimary
        numLabel.textAlignment = .center
        numLabel.translatesAutoresizingMaskIntoConstraints = false

        let iconLabel = UILabel()
        iconLabel.text = hasReading ? "✓" : ""
        iconLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        iconLabel.textColor = .white
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(dayLabel)
        container.addSubview(numLabel)
        container.addSubview(iconLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 56),

            dayLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            dayLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            numLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            numLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            iconLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            iconLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor)
        ])

        return container
    }

    private func refreshShop() {
        shopStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let manager = RewardManager.shared
        let heartsManager = HeartsManager.shared

        for (index, item) in ShopCatalog.allItems.enumerated() {
            let canAfford: Bool
            let statusText: String?

            if ShopCatalog.heartItemIDs.contains(item.id) {
                // Heart items: determine affordability and status
                switch item.id {
                case "hearts_5":
                    canAfford = manager.coins >= item.price && heartsManager.hearts < heartsManager.maxHearts
                    statusText = "❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)"
                case "hearts_refill":
                    let needsRefill = heartsManager.hearts < heartsManager.maxHearts
                    canAfford = manager.coins >= item.price && needsRefill
                    statusText = "❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)"
                case "hearts_upgrade":
                    let canUpgrade = heartsManager.canUpgradeMaxHearts
                    canAfford = canUpgrade // No coin cost for upgrade (handled in purchase logic)
                    statusText = "上限 \(heartsManager.maxHearts) → \(min(heartsManager.maxHearts + 2, 30))"
                default:
                    canAfford = manager.coins >= item.price
                    statusText = nil
                }
            } else {
                canAfford = manager.coins >= item.price
                statusText = nil
            }

            let row = createShopItemRow(item: item, canAfford: canAfford, statusText: statusText)
            shopStack.addArrangedSubview(row)

            if index < ShopCatalog.allItems.count - 1 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                shopStack.addArrangedSubview(sep)
            }
        }
    }

    private func createShopItemRow(item: ShopItem, canAfford: Bool, statusText: String? = nil) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconLabel = UILabel()
        iconLabel.text = item.icon
        iconLabel.font = UIFont.systemFont(ofSize: 24)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = item.name
        nameLabel.font = UIFont.systemFont(ofSize: 15)
        nameLabel.textColor = .textPrimary
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let priceLabel = UILabel()
        priceLabel.text = item.price > 0 ? "💰 \(item.price)" : (statusText ?? "")
        priceLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        priceLabel.textColor = canAfford ? .accent : .textTertiary
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Status label for heart items (shows current hearts / max)
        let extraLabel = UILabel()
        extraLabel.font = UIFont.systemFont(ofSize: 11)
        extraLabel.textColor = .textTertiary
        extraLabel.translatesAutoresizingMaskIntoConstraints = false
        if let status = statusText {
            extraLabel.text = status
        }

        let buyButton = UIButton(type: .system)
        if item.id == "hearts_upgrade" && !HeartsManager.shared.canUpgradeMaxHearts {
            buyButton.setTitle("已满", for: .normal)
            buyButton.setTitleColor(.textTertiary, for: .normal)
        } else {
            buyButton.setTitle("购买", for: .normal)
            buyButton.setTitleColor(canAfford ? .white : .textTertiary, for: .normal)
        }
        buyButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        buyButton.backgroundColor = canAfford ? .primary : .separator
        buyButton.layer.cornerRadius = 6
        buyButton.isEnabled = canAfford
        buyButton.translatesAutoresizingMaskIntoConstraints = false
        buyButton.tag = ShopCatalog.allItems.firstIndex(where: { $0.id == item.id }) ?? 0
        buyButton.addTarget(self, action: #selector(buyButtonTapped(_:)), for: .touchUpInside)
        buyButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
        buyButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        container.addSubview(iconLabel)
        container.addSubview(nameLabel)
        container.addSubview(priceLabel)
        container.addSubview(extraLabel)
        container.addSubview(buyButton)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 48),

            iconLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            iconLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),

            priceLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            priceLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),

            extraLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            extraLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            extraLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -4),

            buyButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            buyButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    private func refreshInventory() {
        // Remove all but keep the empty label if it exists
        let emptyLabel = inventoryStack.arrangedSubviews.first(where: { $0.tag == 999 })
        inventoryStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let items = RewardManager.shared.inventoryItems.filter { !$0.isRedeemed }

        if items.isEmpty {
            if let emptyLabel = emptyLabel {
                inventoryStack.addArrangedSubview(emptyLabel)
            }
            return
        }

        for (index, item) in items.enumerated() {
            let row = createInventoryItemRow(item: item)
            inventoryStack.addArrangedSubview(row)

            if index < items.count - 1 {
                let sep = UIView()
                sep.backgroundColor = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                inventoryStack.addArrangedSubview(sep)
            }
        }
    }

    private func createInventoryItemRow(item: InventoryItem) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconLabel = UILabel()
        iconLabel.text = item.icon
        iconLabel.font = UIFont.systemFont(ofSize: 24)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.text = item.name
        nameLabel.font = UIFont.systemFont(ofSize: 15)
        nameLabel.textColor = .textPrimary
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        let sourceLabel = UILabel()
        switch item.source {
        case .shop:
            sourceLabel.text = "购买获得"
        case .checkIn3:
            sourceLabel.text = "签到3天"
        case .checkIn7:
            sourceLabel.text = "签到7天"
        }
        sourceLabel.font = UIFont.systemFont(ofSize: 11)
        sourceLabel.textColor = .textTertiary
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false

        let redeemButton = UIButton(type: .system)
        redeemButton.setTitle("核销", for: .normal)
        redeemButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        redeemButton.backgroundColor = .successGreen
        redeemButton.setTitleColor(.white, for: .normal)
        redeemButton.layer.cornerRadius = 6
        redeemButton.translatesAutoresizingMaskIntoConstraints = false
        redeemButton.accessibilityIdentifier = item.id
        redeemButton.addTarget(self, action: #selector(redeemButtonTapped(_:)), for: .touchUpInside)
        redeemButton.widthAnchor.constraint(equalToConstant: 50).isActive = true
        redeemButton.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let dateLabel = UILabel()
        dateLabel.text = item.acquiredDate.shortChineseFormat
        dateLabel.font = UIFont.systemFont(ofSize: 11)
        dateLabel.textColor = .textTertiary
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconLabel)
        container.addSubview(nameLabel)
        container.addSubview(sourceLabel)
        container.addSubview(dateLabel)
        container.addSubview(redeemButton)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 50),

            iconLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            iconLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: iconLabel.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),

            sourceLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sourceLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            dateLabel.leadingAnchor.constraint(equalTo: sourceLabel.trailingAnchor, constant: 6),
            dateLabel.centerYAnchor.constraint(equalTo: sourceLabel.centerYAnchor),
            dateLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            redeemButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            redeemButton.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        return container
    }

    // MARK: - Actions

    @objc private func buyButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < ShopCatalog.allItems.count else { return }
        let item = ShopCatalog.allItems[index]

        let manager = RewardManager.shared

        // Handle heart items specially — they affect HeartsManager directly, not inventory
        if ShopCatalog.heartItemIDs.contains(item.id) {
            handleHeartPurchase(item: item)
            return
        }

        guard manager.coins >= item.price else {
            showAlert(title: "金币不足", message: "你需要 \(item.price) 个金币来购买「\(item.name)」，当前有 \(manager.coins) 个金币。")
            return
        }

        let alert = UIAlertController(
            title: "确认购买",
            message: "花费 💰 \(item.price) 购买「\(item.name)」？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "购买", style: .default) { [weak self] _ in
            if manager.spendCoins(item.price) {
                manager.addInventoryItem(shopItem: item, source: .shop)
                self?.refreshAll()
                self?.showAlert(title: "购买成功", message: "「\(item.name)」已加入库存！")
            }
        })
        present(alert, animated: true)
    }
    
    // MARK: - Heart Purchase Handling
    
    private func handleHeartPurchase(item: ShopItem) {
        let manager = RewardManager.shared
        let heartsManager = HeartsManager.shared
        
        switch item.id {
        case "hearts_5":
            guard manager.coins >= 20 else {
                showAlert(title: "金币不足", message: "你需要 20 个金币来购买五颗红心，当前有 \(manager.coins) 个金币。")
                return
            }
            guard heartsManager.hearts < heartsManager.maxHearts else {
                showAlert(title: "红心已满", message: "你的红心已经满了，不需要购买。")
                return
            }
            
            let alert = UIAlertController(
                title: "确认购买",
                message: "花费 💰 20 购买五颗红心？\n当前：❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "购买", style: .default) { [weak self] _ in
                guard manager.spendCoins(20) else { return }
                let added = heartsManager.buyFiveHearts()
                self?.refreshAll()
                if added > 0 {
                    self?.showAlert(title: "购买成功", message: "获得 \(added) 颗红心！当前：❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)")
                }
            })
            present(alert, animated: true)
            
        case "hearts_refill":
            guard manager.coins >= 50 else {
                showAlert(title: "金币不足", message: "你需要 50 个金币来补满红心，当前有 \(manager.coins) 个金币。")
                return
            }
            guard heartsManager.hearts < heartsManager.maxHearts else {
                showAlert(title: "红心已满", message: "你的红心已经是满的，不需要补满。")
                return
            }
            
            let alert = UIAlertController(
                title: "确认购买",
                message: "花费 💰 50 补满红心？\n当前：❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "购买", style: .default) { [weak self] _ in
                guard manager.spendCoins(50) else { return }
                let added = heartsManager.refillHearts()
                self?.refreshAll()
                self?.showAlert(title: "补满成功", message: "补满 \(added) 颗红心！当前：❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)")
            })
            present(alert, animated: true)
            
        case "hearts_upgrade":
            guard heartsManager.canUpgradeMaxHearts else {
                showAlert(title: "已达上限", message: "红心上限已达到最大值 30，无法继续提升。")
                return
            }
            
            let upgradeCost = 100
            guard manager.coins >= upgradeCost else {
                showAlert(title: "金币不足", message: "你需要 \(upgradeCost) 个金币来提升红心上限，当前有 \(manager.coins) 个金币。")
                return
            }
            
            let newMax = min(heartsManager.maxHearts + 2, 30)
            let alert = UIAlertController(
                title: "确认购买",
                message: "花费 💰 \(upgradeCost) 将红心上限从 \(heartsManager.maxHearts) 提升到 \(newMax)？",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "购买", style: .default) { [weak self] _ in
                guard manager.spendCoins(upgradeCost) else { return }
                guard heartsManager.upgradeMaxHearts() else {
                    self?.showAlert(title: "升级失败", message: "红心上限已达到最大值。")
                    return
                }
                self?.refreshAll()
                self?.showAlert(title: "升级成功", message: "红心上限已提升到 \(heartsManager.maxHearts)！")
            })
            present(alert, animated: true)
            
        default:
            break
        }
    }

    @objc private func redeemButtonTapped(_ sender: UIButton) {
        guard let itemId = sender.accessibilityIdentifier else { return }
        let items = RewardManager.shared.inventoryItems
        guard let item = items.first(where: { $0.id == itemId }) else { return }

        let alert = UIAlertController(
            title: "核销奖励",
            message: "确认核销「\(item.name)」？\n核销后将从库存中移除，代表已在现实中兑现。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认核销", style: .default) { [weak self] _ in
            RewardManager.shared.redeemInventoryItem(withId: itemId)
            self?.refreshAll()
            self?.showAlert(title: "核销成功", message: "「\(item.name)」已核销！奖励已兑现。")
        })
        present(alert, animated: true)
    }
}
