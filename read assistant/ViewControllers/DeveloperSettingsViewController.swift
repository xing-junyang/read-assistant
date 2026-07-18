import UIKit

// MARK: - Developer Settings View Controller
/// Allows developers to modify API key, model, and base URL.
/// Access is protected by password verification.
final class DeveloperSettingsViewController: UIViewController {

    // MARK: - Properties
    private let settingsManager = DeveloperSettingsManager.shared
    private let tableView = UITableView(frame: .zero, style: .grouped)

    private enum Row: Int, CaseIterable {
        case apiKey
        case model
        case baseURL

        var title: String {
            switch self {
            case .apiKey: return "API Key"
            case .model: return "模型 (Model)"
            case .baseURL: return "Base URL"
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
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        if let reusedCell = tableView.dequeueReusableCell(withIdentifier: "DevCell") {
            cell = reusedCell
        } else {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "DevCell")
        }
        guard let row = Row(rawValue: indexPath.row) else { return cell }

        let value = storedValue(for: row)
        let hasCustomValue = value != nil && !value!.isEmpty

        cell.textLabel?.text = row.title
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary

        // Show value as detail
        if hasCustomValue {
            let displayValue: String
            if row == .apiKey {
                // Mask API key for security
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
        return cell
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return "此处配置将覆盖默认值。优先级：开发者设置 > 默认值。"
    }
}

// MARK: - UITableViewDelegate
extension DeveloperSettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = Row(rawValue: indexPath.row) else { return }
        editValue(for: row)
    }
}
