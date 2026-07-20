import UIKit

// MARK: - Developer Settings View Controller
/// Allows developers to modify API key, model, and base URL.
/// Access is protected by password verification.
final class DeveloperSettingsViewController: UIViewController {

    // MARK: - Properties
    private let settingsManager = DeveloperSettingsManager.shared
    private let tableView = UITableView(frame: .zero, style: .grouped)

    private enum Section: Int, CaseIterable {
        case api
        case rewards
        case quiz
        case quizCoins
        case gameCoins
        case hearts

        var title: String {
            switch self {
            case .api: return "API 配置"
            case .rewards: return "奖励数据调试"
            case .quiz: return "闯关数据调试"
            case .quizCoins: return "闯关金币设置"
            case .gameCoins: return "小游戏金币设置"
            case .hearts: return "红心调试"
            }
        }
    }

    private enum Row: Int, CaseIterable {
        case apiKey
        case model
        case baseURL

        var title: String {
            switch self {
            case .apiKey: return "API 密钥"
            case .model: return "模型"
            case .baseURL: return "基础 URL"
            }
        }

        var placeholder: String {
            switch self {
            case .apiKey: return "sk-..."
            case .model: return "qwen3-vl-plus"
            case .baseURL: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
            }
        }
    }

    private enum RewardRow: Int, CaseIterable {
        case setXP
        case addXP
        case setCoins
        case addCoins
        case addCheckInDays
        case addInventoryItem
        case clearInventory
        case resetAllRewards

        var title: String {
            switch self {
            case .setXP: return "设置经验值"
            case .addXP: return "增加经验值"
            case .setCoins: return "设置金币"
            case .addCoins: return "增加金币"
            case .addCheckInDays: return "添加签到记录（最近N天）"
            case .addInventoryItem: return "添加库存物品"
            case .clearInventory: return "清空库存"
            case .resetAllRewards: return "重置所有奖励数据"
            }
        }
    }

    private enum QuizRow: Int, CaseIterable {
        case setLevel
        case resetLevels

        var title: String {
            switch self {
            case .setLevel: return "设置闯关数"
            case .resetLevels: return "重置闯关数（归零）"
            }
        }
    }

    private enum HeartRow: Int, CaseIterable {
        case toggleUnlimited
        case setHearts
        case setMaxHearts
        case setRegenerationInterval
        case refillHearts

        var title: String {
            switch self {
            case .toggleUnlimited: return "无限红心模式"
            case .setHearts: return "设置红心数量"
            case .setMaxHearts: return "设置红心上限"
            case .setRegenerationInterval: return "红心恢复时间（秒）"
            case .refillHearts: return "补满红心"
            }
        }
    }

    private enum QuizCoinsRow: Int, CaseIterable {
        case setCostCoins
        case setRewardCoins
        case toggleConsecutiveVictoryBonus

        var title: String {
            switch self {
            case .setCostCoins: return "闯关消耗金币数"
            case .setRewardCoins: return "完全胜利奖励金币数"
            case .toggleConsecutiveVictoryBonus: return "连续完全胜利加成"
            }
        }
    }

    private enum GameCoinsRow: Int, CaseIterable {
        case setIdiomChainCost
        case setCharacterMatchCost
        case setIdiomWordleCost
        case setBattlefieldCost
        case setSubwaySurferCost
        case setFlappyBirdCost
        case setSkillSnakeCost

        var title: String {
            switch self {
            case .setIdiomChainCost: return "汉字拼图消耗金币数"
            case .setCharacterMatchCost: return "汉字消消乐消耗金币数"
            case .setIdiomWordleCost: return "成语猜猜乐消耗金币数"
            case .setBattlefieldCost: return "战地枪战消耗金币数"
            case .setSubwaySurferCost: return "地铁跑酷消耗金币数"
            case .setFlappyBirdCost: return "Flappy Bird消耗金币数"
            case .setSkillSnakeCost: return "技能贪吃蛇消耗金币数"
            }
        }
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI Setup
    private func setupUI() {
        title = "开发者设置"
        view.backgroundColor = .background

        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Add reset button in footer
        let footerView = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 80))
        let resetButton = UIButton(type: .system)
        resetButton.setTitle("恢复默认设置", for: .normal)
        resetButton.setTitleColor(.errorRed, for: .normal)
        resetButton.addTarget(self, action: #selector(resetToDefaults), for: .touchUpInside)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(resetButton)
        NSLayoutConstraint.activate([
            resetButton.centerXAnchor.constraint(equalTo: footerView.centerXAnchor),
            resetButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor)
        ])
        tableView.tableFooterView = footerView
    }

    // MARK: - Actions
    private func editValue(for row: Row) {
        let currentValue = storedValue(for: row) ?? ""

        let alert = UIAlertController(
            title: "编辑 \(row.title)",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.text = currentValue
            textField.placeholder = row.placeholder
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
            if row == .apiKey {
                textField.isSecureTextEntry = true
            }
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                self?.showAlert(title: "错误", message: "输入不能为空")
                return
            }
            self?.saveValue(text, for: row)
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    @objc private func resetToDefaults() {
        showConfirm(title: "恢复默认设置", message: "确定要恢复所有开发者设置为默认值吗？") { [weak self] in
            self?.settingsManager.resetToDefaults()
            self?.tableView.reloadData()
            self?.showAlert(title: "完成", message: "已恢复默认设置")
        }
    }

    // MARK: - Storage
    private func storedValue(for row: Row) -> String? {
        switch row {
        case .apiKey:
            return settingsManager.apiKey
        case .model:
            return settingsManager.model
        case .baseURL:
            return settingsManager.baseURL
        }
    }

    private func saveValue(_ value: String, for row: Row) {
        switch row {
        case .apiKey:
            settingsManager.apiKey = value
        case .model:
            settingsManager.model = value
        case .baseURL:
            settingsManager.baseURL = value
        }
    }
}

// MARK: - UITableViewDataSource
extension DeveloperSettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionType = Section(rawValue: section) else { return 0 }
        switch sectionType {
        case .api:
            return Row.allCases.count
        case .rewards:
            return RewardRow.allCases.count
        case .quiz:
            return QuizRow.allCases.count
        case .quizCoins:
            return QuizCoinsRow.allCases.count
        case .gameCoins:
            return GameCoinsRow.allCases.count
        case .hearts:
            return HeartRow.allCases.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        if let reusedCell = tableView.dequeueReusableCell(withIdentifier: "DevCell") {
            cell = reusedCell
        } else {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "DevCell")
        }

        guard let sectionType = Section(rawValue: indexPath.section) else { return cell }

        switch sectionType {
        case .api:
            configureAPICell(cell, at: indexPath)
        case .rewards:
            configureRewardCell(cell, at: indexPath)
        case .quiz:
            configureQuizCell(cell, at: indexPath)
        case .quizCoins:
            configureQuizCoinsCell(cell, at: indexPath)
        case .gameCoins:
            configureGameCoinsCell(cell, at: indexPath)
        case .hearts:
            configureHeartCell(cell, at: indexPath)
        }

        return cell
    }

    private func configureAPICell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let row = Row(rawValue: indexPath.row) else { return }

        let value = storedValue(for: row)
        let hasCustomValue = value != nil && !value!.isEmpty

        cell.textLabel?.text = row.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary

        if hasCustomValue {
            let displayValue: String
            if row == .apiKey {
                displayValue = String(value!.prefix(8)) + "••••••••"
            } else {
                displayValue = value!
            }
            cell.detailTextLabel?.text = displayValue
            cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
            cell.detailTextLabel?.textColor = .textSecondary
        } else {
            cell.detailTextLabel?.text = "使用默认值"
            cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
            cell.detailTextLabel?.textColor = .textTertiary
        }

        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .cardBackground
    }

    private func configureRewardCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let row = RewardRow(rawValue: indexPath.row) else { return }
        let manager = RewardManager.shared

        cell.textLabel?.text = row.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)

        switch row {
        case .setXP, .addXP:
            cell.detailTextLabel?.text = "当前: \(manager.totalXP) XP (Lv.\(manager.currentLevel))"
            cell.detailTextLabel?.textColor = .textSecondary
        case .setCoins, .addCoins:
            cell.detailTextLabel?.text = "当前: 💰 \(manager.coins)"
            cell.detailTextLabel?.textColor = .textSecondary
        case .addCheckInDays:
            cell.detailTextLabel?.text = "连续签到: \(manager.currentStreak()) 天"
            cell.detailTextLabel?.textColor = .textSecondary
        case .addInventoryItem:
            cell.detailTextLabel?.text = "库存物品: \(manager.inventoryItems.count) 件"
            cell.detailTextLabel?.textColor = .textSecondary
        case .clearInventory:
            cell.detailTextLabel?.text = "库存物品: \(manager.inventoryItems.count) 件"
            cell.detailTextLabel?.textColor = .errorRed
        case .resetAllRewards:
            cell.detailTextLabel?.text = "⚠️ 不可恢复"
            cell.detailTextLabel?.textColor = .errorRed
        }

        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .cardBackground
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let sectionType = Section(rawValue: section) else { return nil }
        switch sectionType {
        case .api:
            return "此处配置将覆盖默认值。优先级：开发者设置 > 默认值。"
        case .rewards:
            return "调试用：可直接修改奖励数据，方便测试各功能。"
        case .quiz:
            return "调试用：可设置或重置闯关进度。"
        case .quizCoins:
            return "自定义闯关消耗和奖励的金币数量。连续完全胜利加成：每次完全胜利额外加1金币（第2连胜+2，第3连胜+3，依此类推）。"
        case .gameCoins:
            return "自定义小游戏消耗的金币数量。汉字拼图默认10金币，汉字消消乐默认20金币，成语猜猜乐默认15金币，战地枪战默认20金币。"
        case .hearts:
            return "调试用：可开关无限红心模式、修改红心数量和上限、设置恢复时间。"
        }
    }
}

// MARK: - UITableViewDelegate
extension DeveloperSettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let sectionType = Section(rawValue: indexPath.section) else { return }
        
        switch sectionType {
        case .api:
            guard let row = Row(rawValue: indexPath.row) else { return }
            editValue(for: row)
        case .rewards:
            guard let row = RewardRow(rawValue: indexPath.row) else { return }
            handleRewardAction(for: row)
        case .quiz:
            guard let row = QuizRow(rawValue: indexPath.row) else { return }
            handleQuizAction(for: row)
        case .quizCoins:
            guard let row = QuizCoinsRow(rawValue: indexPath.row) else { return }
            handleQuizCoinsAction(for: row)
        case .gameCoins:
            guard let row = GameCoinsRow(rawValue: indexPath.row) else { return }
            handleGameCoinsAction(for: row)
        case .hearts:
            guard let row = HeartRow(rawValue: indexPath.row) else { return }
            handleHeartAction(for: row)
        }
    }
    
    // MARK: - Reward Debug Actions
    
    private func handleRewardAction(for row: RewardRow) {
        switch row {
        case .setXP:
            showNumberInput(title: "设置经验值", message: "当前: \(RewardManager.shared.totalXP) XP", currentValue: "\(RewardManager.shared.totalXP)") { value in
                RewardManager.shared.totalXP = value
                self.tableView.reloadData()
                self.showAlert(title: "完成", message: "经验值已设置为 \(value)")
            }
        case .addXP:
            showNumberInput(title: "增加经验值", message: "当前: \(RewardManager.shared.totalXP) XP", currentValue: "100") { value in
                RewardManager.shared.totalXP += value
                self.tableView.reloadData()
                let newLevel = RewardManager.shared.currentLevel
                self.showAlert(title: "完成", message: "经验值 +\(value)，当前 Lv.\(newLevel)")
            }
        case .setCoins:
            showNumberInput(title: "设置金币", message: "当前: 💰 \(RewardManager.shared.coins)", currentValue: "\(RewardManager.shared.coins)") { value in
                RewardManager.shared.coins = value
                self.tableView.reloadData()
                self.showAlert(title: "完成", message: "金币已设置为 \(value)")
            }
        case .addCoins:
            showNumberInput(title: "增加金币", message: "当前: 💰 \(RewardManager.shared.coins)", currentValue: "50") { value in
                RewardManager.shared.coins += value
                self.tableView.reloadData()
                self.showAlert(title: "完成", message: "金币 +\(value)，当前 💰 \(RewardManager.shared.coins)")
            }
        case .addCheckInDays:
            showNumberInput(title: "添加签到记录", message: "将最近 N 天全部标记为已签到", currentValue: "7") { days in
                self.addMockCheckInRecords(days: days)
            }
        case .addInventoryItem:
            showInventoryItemPicker()
        case .clearInventory:
            showConfirm(title: "清空库存", message: "确定要移除所有库存物品吗？此操作不可恢复。") { [weak self] in
                RewardManager.shared.inventoryItems = []
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "库存已清空")
            }
        case .resetAllRewards:
            showConfirm(title: "⚠️ 重置所有奖励数据", message: "将清空经验值、金币、签到记录和库存。此操作不可恢复！") { [weak self] in
                let manager = RewardManager.shared
                manager.totalXP = 0
                manager.coins = 0
                manager.inventoryItems = []
                manager.checkInRecords = []
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "所有奖励数据已重置")
            }
        }
    }

    // MARK: - Quiz Debug Actions

    private func configureQuizCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let row = QuizRow(rawValue: indexPath.row) else { return }
        let manager = WrongAnswerBookManager.shared

        cell.textLabel?.text = row.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)

        switch row {
        case .setLevel:
            cell.detailTextLabel?.text = "当前: \(manager.totalLevelsCompleted) 关"
            cell.detailTextLabel?.textColor = .textSecondary
        case .resetLevels:
            cell.detailTextLabel?.text = "⚠️ 当前: \(manager.totalLevelsCompleted) 关，重置后不可恢复"
            cell.detailTextLabel?.textColor = .errorRed
        }

        cell.accessoryType = .disclosureIndicator
        cell.backgroundColor = .cardBackground
    }

    private func configureHeartCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let row = HeartRow(rawValue: indexPath.row) else { return }
        let heartsManager = HeartsManager.shared

        cell.textLabel?.text = row.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)

        switch row {
        case .toggleUnlimited:
            if heartsManager.unlimitedHearts {
                cell.detailTextLabel?.text = "当前: ✅ 已开启 ∞"
                cell.detailTextLabel?.textColor = .successGreen
            } else {
                cell.detailTextLabel?.text = "当前: ❌ 已关闭"
                cell.detailTextLabel?.textColor = .textSecondary
            }
            cell.accessoryType = .none
        case .setHearts:
            cell.detailTextLabel?.text = "当前: ❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)"
            cell.detailTextLabel?.textColor = .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setMaxHearts:
            cell.detailTextLabel?.text = "当前上限: \(heartsManager.maxHearts) (最大30)"
            cell.detailTextLabel?.textColor = .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setRegenerationInterval:
            let devSettings = DeveloperSettingsManager.shared
            let interval = devSettings.effectiveHeartRegenerationInterval
            let minutes = Int(interval) / 60
            let seconds = Int(interval) % 60
            let hasOverride = devSettings.heartRegenerationInterval != nil
            cell.detailTextLabel?.text = "\(minutes)分\(seconds)秒 (\(Int(interval))秒)\(hasOverride ? " [自定义]" : "")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .refillHearts:
            cell.detailTextLabel?.text = "补满到 \(heartsManager.maxHearts) 颗"
            cell.detailTextLabel?.textColor = .textSecondary
            cell.accessoryType = .disclosureIndicator
        }

        cell.backgroundColor = .cardBackground
    }

    private func configureQuizCoinsCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let row = QuizCoinsRow(rawValue: indexPath.row) else { return }
        let devSettings = DeveloperSettingsManager.shared

        cell.textLabel?.text = row.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)

        switch row {
        case .setCostCoins:
            let cost = devSettings.effectiveQuizCostCoins
            let hasOverride = devSettings.quizCostCoins != nil
            cell.detailTextLabel?.text = "当前: \(cost)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setRewardCoins:
            let reward = devSettings.effectiveQuizRewardCoins
            let hasOverride = devSettings.quizRewardCoins != nil
            cell.detailTextLabel?.text = "当前: \(reward)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .toggleConsecutiveVictoryBonus:
            let enabled = devSettings.effectiveConsecutiveVictoryBonusEnabled
            let hasOverride = devSettings.consecutiveVictoryBonusEnabled != nil
            cell.detailTextLabel?.text = enabled ? "✅ 已开启\(hasOverride ? " [自定义]" : "")" : "❌ 已关闭\(hasOverride ? " [自定义]" : "")"
            cell.detailTextLabel?.textColor = enabled ? .successGreen : .textSecondary
            cell.accessoryType = .none
        }

        cell.backgroundColor = .cardBackground
    }

    private func handleQuizAction(for row: QuizRow) {
        let manager = WrongAnswerBookManager.shared
        switch row {
        case .setLevel:
            showNumberInput(title: "设置闯关数", message: "当前: \(manager.totalLevelsCompleted) 关", currentValue: "\(manager.totalLevelsCompleted)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "闯关数不能为负数")
                    return
                }
                manager.setTotalLevelsCompleted(value)
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "闯关数已设置为 \(value)")
            }
        case .resetLevels:
            showConfirm(title: "重置闯关数", message: "确定要将闯关数归零吗？闯关记录将全部清除。") { [weak self] in
                manager.setTotalLevelsCompleted(0)
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "闯关数已重置为 0")
            }
        }
    }
    
    // MARK: - Heart Debug Actions
    
    private func handleHeartAction(for row: HeartRow) {
        let heartsManager = HeartsManager.shared
        
        switch row {
        case .toggleUnlimited:
            let newValue = !heartsManager.unlimitedHearts
            heartsManager.unlimitedHearts = newValue
            if newValue {
                heartsManager.debugRefillHearts()
            }
            tableView.reloadData()
            showAlert(title: "完成", message: newValue ? "无限红心模式已开启 ∞" : "无限红心模式已关闭")
            
        case .setHearts:
            showNumberInput(title: "设置红心数量", message: "当前: ❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)", currentValue: "\(heartsManager.hearts)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "红心数量不能为负数")
                    return
                }
                heartsManager.debugSetHearts(value)
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "红心数量已设置为 \(heartsManager.hearts)")
            }
            
        case .setMaxHearts:
            showNumberInput(title: "设置红心上限", message: "当前: \(heartsManager.maxHearts) (最大30)", currentValue: "\(heartsManager.maxHearts)") { [weak self] value in
                guard value >= 1, value <= 30 else {
                    self?.showAlert(title: "错误", message: "红心上限必须在 1 到 30 之间")
                    return
                }
                heartsManager.debugSetMaxHearts(value)
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "红心上限已设置为 \(heartsManager.maxHearts)")
            }

        case .setRegenerationInterval:
            let devSettings = DeveloperSettingsManager.shared
            let currentInterval = devSettings.effectiveHeartRegenerationInterval
            let currentMinutes = Int(currentInterval) / 60
            showNumberInput(title: "红心恢复时间（秒）", message: "当前: \(currentMinutes)分\(Int(currentInterval) % 60)秒 (\(Int(currentInterval))秒)\n默认: 600秒（10分钟）", currentValue: "\(Int(currentInterval))") { [weak self] value in
                guard value >= 10 else {
                    self?.showAlert(title: "错误", message: "恢复时间不能少于 10 秒")
                    return
                }
                if value == Int(DeveloperSettingsManager.defaultHeartRegenerationInterval) {
                    devSettings.heartRegenerationInterval = nil  // Reset to default
                } else {
                    devSettings.heartRegenerationInterval = TimeInterval(value)
                }
                self?.tableView.reloadData()
                let minutes = value / 60
                let seconds = value % 60
                self?.showAlert(title: "完成", message: "红心恢复时间已设置为 \(minutes)分\(seconds)秒")
            }
            
        case .refillHearts:
            heartsManager.debugRefillHearts()
            tableView.reloadData()
            showAlert(title: "完成", message: "红心已补满！当前：❤️ \(heartsManager.hearts)/\(heartsManager.maxHearts)")
        }
    }

    // MARK: - Quiz Coins Debug Actions

    private func handleQuizCoinsAction(for row: QuizCoinsRow) {
        let devSettings = DeveloperSettingsManager.shared

        switch row {
        case .setCostCoins:
            let currentCost = devSettings.effectiveQuizCostCoins
            showNumberInput(title: "闯关消耗金币数", message: "当前: \(currentCost)💰\n默认: \(DeveloperSettingsManager.defaultQuizCostCoins)💰", currentValue: "\(currentCost)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "消耗金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultQuizCostCoins {
                    devSettings.quizCostCoins = nil
                } else {
                    devSettings.quizCostCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "闯关消耗已设置为 \(value)💰")
            }

        case .setRewardCoins:
            let currentReward = devSettings.effectiveQuizRewardCoins
            showNumberInput(title: "完全胜利奖励金币数", message: "当前: \(currentReward)💰\n默认: \(DeveloperSettingsManager.defaultQuizRewardCoins)💰", currentValue: "\(currentReward)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "奖励金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultQuizRewardCoins {
                    devSettings.quizRewardCoins = nil
                } else {
                    devSettings.quizRewardCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "完全胜利奖励已设置为 \(value)💰")
            }

        case .toggleConsecutiveVictoryBonus:
            let currentValue = devSettings.effectiveConsecutiveVictoryBonusEnabled
            let newValue = !currentValue
            if newValue == DeveloperSettingsManager.defaultConsecutiveVictoryBonusEnabled {
                devSettings.consecutiveVictoryBonusEnabled = nil
            } else {
                devSettings.consecutiveVictoryBonusEnabled = newValue
            }
            tableView.reloadData()
            showAlert(title: "完成", message: newValue ? "连续完全胜利加成已开启 🔥" : "连续完全胜利加成已关闭")
        }
    }
    
    // MARK: - Game Coins Debug Actions

    private func configureGameCoinsCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        guard let row = GameCoinsRow(rawValue: indexPath.row) else { return }
        let devSettings = DeveloperSettingsManager.shared

        cell.textLabel?.text = row.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)

        switch row {
        case .setIdiomChainCost:
            let cost = devSettings.effectiveIdiomChainCostCoins
            let hasOverride = devSettings.idiomChainCostCoins != nil
            cell.detailTextLabel?.text = "当前: \(cost)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setCharacterMatchCost:
            let cost = devSettings.effectiveCharacterMatchCostCoins
            let hasOverride = devSettings.characterMatchCostCoins != nil
            cell.detailTextLabel?.text = "当前: \(cost)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setIdiomWordleCost:
            let cost = devSettings.effectiveIdiomWordleCostCoins
            let hasOverride = devSettings.idiomWordleCostCoins != nil
            cell.detailTextLabel?.text = "当前: \(cost)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setBattlefieldCost:
            let cost = devSettings.effectiveBattlefieldCostCoins
            let hasOverride = devSettings.battlefieldCostCoins != nil
            cell.detailTextLabel?.text = "当前: \(cost)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setSubwaySurferCost:
            let cost = devSettings.effectiveSubwaySurferCostCoins
            let hasOverride = devSettings.subwaySurferCostCoins != nil
            cell.detailTextLabel?.text = "当前: \(cost)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setFlappyBirdCost:
            let cost = devSettings.effectiveFlappyBirdCostCoins
            let hasOverride = devSettings.flappyBirdCostCoins != nil
            cell.detailTextLabel?.text = "当前: \(cost)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        case .setSkillSnakeCost:
            let cost = devSettings.effectiveSkillSnakeCostCoins
            let hasOverride = devSettings.skillSnakeCostCoins != nil
            cell.detailTextLabel?.text = "当前: \(cost)💰\(hasOverride ? " [自定义]" : " (默认)")"
            cell.detailTextLabel?.textColor = hasOverride ? .primary : .textSecondary
            cell.accessoryType = .disclosureIndicator
        }

        cell.backgroundColor = .cardBackground
    }

    private func handleGameCoinsAction(for row: GameCoinsRow) {
        let devSettings = DeveloperSettingsManager.shared

        switch row {
        case .setIdiomChainCost:
            let currentCost = devSettings.effectiveIdiomChainCostCoins
            showNumberInput(title: "汉字拼图消耗金币数", message: "当前: \(currentCost)💰\n默认: \(DeveloperSettingsManager.defaultIdiomChainCostCoins)💰", currentValue: "\(currentCost)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "消耗金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultIdiomChainCostCoins {
                    devSettings.idiomChainCostCoins = nil
                } else {
                    devSettings.idiomChainCostCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "汉字拼图消耗已设置为 \(value)💰")
            }

        case .setCharacterMatchCost:
            let currentCost = devSettings.effectiveCharacterMatchCostCoins
            showNumberInput(title: "汉字消消乐消耗金币数", message: "当前: \(currentCost)💰\n默认: \(DeveloperSettingsManager.defaultCharacterMatchCostCoins)💰", currentValue: "\(currentCost)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "消耗金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultCharacterMatchCostCoins {
                    devSettings.characterMatchCostCoins = nil
                } else {
                    devSettings.characterMatchCostCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "汉字消消乐消耗已设置为 \(value)💰")
            }

        case .setIdiomWordleCost:
            let currentCost = devSettings.effectiveIdiomWordleCostCoins
            showNumberInput(title: "成语猜猜乐消耗金币数", message: "当前: \(currentCost)💰\n默认: \(DeveloperSettingsManager.defaultIdiomWordleCostCoins)💰", currentValue: "\(currentCost)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "消耗金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultIdiomWordleCostCoins {
                    devSettings.idiomWordleCostCoins = nil
                } else {
                    devSettings.idiomWordleCostCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "成语猜猜乐消耗已设置为 \(value)💰")
            }

        case .setBattlefieldCost:
            let currentCost = devSettings.effectiveBattlefieldCostCoins
            showNumberInput(title: "战地枪战消耗金币数", message: "当前: \(currentCost)💰\n默认: \(DeveloperSettingsManager.defaultBattlefieldCostCoins)💰", currentValue: "\(currentCost)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "消耗金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultBattlefieldCostCoins {
                    devSettings.battlefieldCostCoins = nil
                } else {
                    devSettings.battlefieldCostCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "战地枪战消耗已设置为 \(value)💰")
            }

        case .setSubwaySurferCost:
            let currentCost = devSettings.effectiveSubwaySurferCostCoins
            showNumberInput(title: "地铁跑酷消耗金币数", message: "当前: \(currentCost)💰\n默认: \(DeveloperSettingsManager.defaultSubwaySurferCostCoins)💰", currentValue: "\(currentCost)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "消耗金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultSubwaySurferCostCoins {
                    devSettings.subwaySurferCostCoins = nil
                } else {
                    devSettings.subwaySurferCostCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "地铁跑酷消耗已设置为 \(value)💰")
            }

        case .setFlappyBirdCost:
            let currentCost = devSettings.effectiveFlappyBirdCostCoins
            showNumberInput(title: "Flappy Bird消耗金币数", message: "当前: \(currentCost)💰\n默认: \(DeveloperSettingsManager.defaultFlappyBirdCostCoins)💰", currentValue: "\(currentCost)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "消耗金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultFlappyBirdCostCoins {
                    devSettings.flappyBirdCostCoins = nil
                } else {
                    devSettings.flappyBirdCostCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "Flappy Bird消耗已设置为 \(value)💰")
            }

        case .setSkillSnakeCost:
            let currentCost = devSettings.effectiveSkillSnakeCostCoins
            showNumberInput(title: "技能贪吃蛇消耗金币数", message: "当前: \(currentCost)💰\n默认: \(DeveloperSettingsManager.defaultSkillSnakeCostCoins)💰", currentValue: "\(currentCost)") { [weak self] value in
                guard value >= 0 else {
                    self?.showAlert(title: "错误", message: "消耗金币数不能为负数")
                    return
                }
                if value == DeveloperSettingsManager.defaultSkillSnakeCostCoins {
                    devSettings.skillSnakeCostCoins = nil
                } else {
                    devSettings.skillSnakeCostCoins = value
                }
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "技能贪吃蛇消耗已设置为 \(value)💰")
            }
        }
    }
    
    private func showNumberInput(title: String, message: String, currentValue: String, onConfirm: @escaping (Int) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = currentValue
            textField.keyboardType = .numberPad
            textField.placeholder = "请输入数字"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text,
                  let value = Int(text) else {
                self?.showAlert(title: "错误", message: "请输入有效的整数")
                return
            }
            onConfirm(value)
        })
        present(alert, animated: true)
    }
    
    private func addMockCheckInRecords(days: Int) {
        let clampedDays = max(1, min(days, 60))
        let manager = RewardManager.shared
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        var records = manager.checkInRecords
        for i in 0..<clampedDays {
            let date = calendar.date(byAdding: .day, value: -i, to: Date()) ?? Date()
            let dateStr = dateFormatter.string(from: date)
            if !records.contains(where: { $0.date == dateStr }) {
                records.append(CheckInRecord(date: dateStr, hasReading: true, rewardClaimed: nil))
            }
        }
        manager.checkInRecords = records
        tableView.reloadData()
        showAlert(title: "完成", message: "已添加最近 \(clampedDays) 天签到记录，连续签到 \(manager.currentStreak()) 天")
    }
    
    private func showInventoryItemPicker() {
        let manager = RewardManager.shared
        let items = ShopCatalog.allItems
        
        let alert = UIAlertController(title: "添加库存物品", message: "选择一个商品添加到库存", preferredStyle: .actionSheet)
        
        for item in items {
            alert.addAction(UIAlertAction(title: "\(item.icon) \(item.name)", style: .default) { [weak self] _ in
                manager.addInventoryItem(shopItem: item, source: .shop)
                self?.tableView.reloadData()
                self?.showAlert(title: "完成", message: "「\(item.name)」已添加到库存")
            })
        }
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
}
