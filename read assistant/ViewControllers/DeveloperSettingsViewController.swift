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

        var title: String {
            switch self {
            case .api: return "API 配置"
            case .rewards: return "奖励数据调试"
            case .quiz: return "闯关数据调试"
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
