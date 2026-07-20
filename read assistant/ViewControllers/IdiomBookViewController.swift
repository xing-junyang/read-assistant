import UIKit

// MARK: - Idiom Book View Controller
/// Shows built-in and custom idioms, with ability to import new ones.
final class IdiomBookViewController: UIViewController {

    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var customIdioms: [String] = []
    private let builtInCount = IdiomWordleViewController.builtInIdioms.count

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }

    // MARK: - Data
    private func loadData() {
        customIdioms = CustomIdiomManager.shared.customIdioms
        tableView.reloadData()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "成语本"

        // Import button in nav bar
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(importTapped)
        )

        // TableView
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
    }

    // MARK: - Actions
    @objc private func importTapped() {
        let alert = UIAlertController(
            title: "导入成语",
            message: "请输入四字成语，多个成语用空格、逗号或换行分隔。\n只接受四字中文词语。",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "例如：一心一意 三心二意"
            textField.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "导入", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            let count = CustomIdiomManager.shared.importIdioms(from: text)
            self?.loadData()
            let message = count > 0 ? "成功导入 \(count) 个成语" : "未识别到有效的四字成语"
            let resultAlert = UIAlertController(title: "导入结果", message: message, preferredStyle: .alert)
            resultAlert.addAction(UIAlertAction(title: "确定", style: .default))
            self?.present(resultAlert, animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension IdiomBookViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1  // Built-in count summary
        } else {
            return max(1, customIdioms.count)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "内置成语库" : "我的成语 (\(customIdioms.count)个)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        if let dequeued = tableView.dequeueReusableCell(withIdentifier: "IdiomCell") {
            cell = dequeued
        } else {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "IdiomCell")
        }

        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 13)
        cell.backgroundColor = .cardBackground

        if indexPath.section == 0 {
            cell.textLabel?.text = "内置成语"
            cell.detailTextLabel?.text = "共 \(builtInCount) 个经典成语，用于成语猜猜乐游戏"
            cell.detailTextLabel?.textColor = .textSecondary
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            if customIdioms.isEmpty {
                cell.textLabel?.text = "还没有导入成语"
                cell.detailTextLabel?.text = "点击右上角 + 添加四字成语"
                cell.detailTextLabel?.textColor = .textTertiary
                cell.accessoryType = .none
                cell.selectionStyle = .none
            } else {
                let idiom = customIdioms[indexPath.row]
                cell.textLabel?.text = idiom
                cell.detailTextLabel?.text = "自定义导入"
                cell.detailTextLabel?.textColor = .textSecondary
                cell.accessoryType = .none
                cell.selectionStyle = .default
                cell.textLabel?.textColor = .textPrimary
            }
        }

        return cell
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 && !customIdioms.isEmpty {
            return "左滑可删除单个成语。导入的成语会加入成语猜猜乐游戏的词库。"
        }
        return nil
    }
}

// MARK: - UITableViewDelegate
extension IdiomBookViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1 && !customIdioms.isEmpty
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete, indexPath.section == 1 {
            CustomIdiomManager.shared.removeIdiom(at: indexPath.row)
            loadData()
        }
    }
}
