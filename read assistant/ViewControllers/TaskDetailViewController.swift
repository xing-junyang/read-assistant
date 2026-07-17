import UIKit

// MARK: - Task Detail View Controller
/// Shows task details, expected texts, and allows starting a reading session.
final class TaskDetailViewController: UIViewController {

    // MARK: - Properties
    private let taskId: String
    private var task: ReadingTask? {
        return TaskManager.shared.task(withId: taskId)
    }

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let startReadingButton = UIButton(type: .system)

    // MARK: - Initialization
    init(taskId: String) {
        self.taskId = taskId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupStartButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateStartButton()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = task?.title ?? "任务详情"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addExpectedText)
        )
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ExpectedTextCell")
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupStartButton() {
        startReadingButton.setTitle("开始阅读", for: .normal)
        startReadingButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        startReadingButton.setTitleColor(.white, for: .normal)
        startReadingButton.backgroundColor = .primary
        startReadingButton.layer.cornerRadius = 12
        startReadingButton.addTarget(self, action: #selector(startReadingTapped), for: .touchUpInside)
        startReadingButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startReadingButton)

        NSLayoutConstraint.activate([
            startReadingButton.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 12),
            startReadingButton.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -16),
            startReadingButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            startReadingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            startReadingButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func updateStartButton() {
        guard let task = task else { return }
        startReadingButton.isEnabled = !task.expectedTexts.isEmpty
        startReadingButton.alpha = task.expectedTexts.isEmpty ? 0.5 : 1.0
        if task.isCompleted {
            startReadingButton.setTitle("已完成 ✓", for: .normal)
            startReadingButton.backgroundColor = .successGreen
            startReadingButton.isEnabled = false
        } else {
            startReadingButton.setTitle("开始阅读", for: .normal)
            startReadingButton.backgroundColor = .primary
            startReadingButton.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func addExpectedText() {
        showActionSheet(title: "添加阅读文本", actions: [
            ("手动输入", .default, { [weak self] in self?.showManualInput() }),
            ("OCR 拍照识别", .default, { [weak self] in self?.showOCRScanner() })
        ])
    }

    private func showManualInput() {
        // Present a multi-line text input
        let alert = UIAlertController(title: "输入阅读文本", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "请输入期望阅读的文本内容"
        }

        // For multiline, we use a custom approach with a separate VC
        let inputVC = TextInputViewController()
        inputVC.onSave = { [weak self] text in
            guard let self = self, let task = self.task else { return }
            task.expectedTexts.append(text)
            TaskManager.shared.updateTask(task)
            self.tableView.reloadData()
            self.updateStartButton()
        }
        let nav = UINavigationController(rootViewController: inputVC)
        present(nav, animated: true)
    }

    private func showOCRScanner() {
        let ocrVC = OCRScanViewController()
        ocrVC.onTextRecognized = { [weak self] text in
            guard let self = self, let task = self.task else { return }
            task.expectedTexts.append(text)
            TaskManager.shared.updateTask(task)
            self.tableView.reloadData()
            self.updateStartButton()
        }
        let nav = UINavigationController(rootViewController: ocrVC)
        present(nav, animated: true)
    }

    @objc private func startReadingTapped() {
        guard let task = task, !task.expectedTexts.isEmpty else { return }
        let readingVC = ReadingViewController(taskId: task.id)
        navigationController?.pushViewController(readingVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension TaskDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let task = task else { return 0 }
        if section == 0 {
            return task.expectedTexts.isEmpty ? 1 : task.expectedTexts.count
        } else {
            return task.sessions.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "期望阅读文本" : "历史阅读记录"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let task = task else { return UITableViewCell() }

        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ExpectedTextCell", for: indexPath)
            cell.selectionStyle = .none

            if task.expectedTexts.isEmpty {
                cell.textLabel?.text = "暂无文本，点击右上角 + 添加"
                cell.textLabel?.textColor = .textTertiary
                cell.accessoryType = .none
            } else {
                let text = task.expectedTexts[indexPath.row]
                cell.textLabel?.text = text.truncated(80)
                cell.textLabel?.textColor = .textPrimary
                cell.textLabel?.numberOfLines = 2

                // Show completion status
                let readIndices = Set(task.sessions.map { $0.expectedTextIndex })
                if readIndices.contains(indexPath.row) {
                    cell.accessoryType = .checkmark
                    cell.tintColor = .successGreen
                } else {
                    cell.accessoryType = .none
                }
            }
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ExpectedTextCell", for: indexPath)
            let session = task.sessions[indexPath.row]
            let textIndex = session.expectedTextIndex
            let preview = textIndex < task.expectedTexts.count ? task.expectedTexts[textIndex].truncated(40) : "未知文本"
            cell.textLabel?.text = "\(indexPath.row + 1). \(preview)"
            cell.textLabel?.numberOfLines = 1
            cell.textLabel?.textColor = .textPrimary

            if let result = session.result {
                cell.detailTextLabel?.text = "得分: \(Int(result.score))%"
                cell.detailTextLabel?.textColor = result.score >= 80 ? .successGreen : .errorRed
            }

            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }
}

// MARK: - UITableViewDelegate
extension TaskDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let task = task else { return }

        if indexPath.section == 0 && !task.expectedTexts.isEmpty {
            // Edit expected text
            let text = task.expectedTexts[indexPath.row]
            let inputVC = TextInputViewController(initialText: text)
            inputVC.onSave = { [weak self] newText in
                guard let self = self, let task = self.task else { return }
                task.expectedTexts[indexPath.row] = newText
                TaskManager.shared.updateTask(task)
                self.tableView.reloadData()
            }
            let nav = UINavigationController(rootViewController: inputVC)
            present(nav, animated: true)
        } else if indexPath.section == 1 {
            // View result
            let session = task.sessions[indexPath.row]
            if let result = session.result {
                let resultVC = ResultViewController(result: result)
                navigationController?.pushViewController(resultVC, animated: true)
            }
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 0 && !(task?.expectedTexts.isEmpty ?? true)
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard indexPath.section == 0 else { return nil }

        let deleteAction = UITableViewRowAction(style: .destructive, title: "删除") { [weak self] _, _ in
            guard let self = self, let task = self.task else { return }
            task.expectedTexts.remove(at: indexPath.row)
            TaskManager.shared.updateTask(task)
            self.tableView.reloadData()
            self.updateStartButton()
        }

        return [deleteAction]
    }
}

// MARK: - Text Input View Controller (inline)
/// Simple multi-line text input view controller.
final class TextInputViewController: UIViewController {

    private let textView = UITextView()
    var initialText: String = ""
    var onSave: ((String) -> Void)?

    init(initialText: String = "") {
        self.initialText = initialText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        title = initialText.isEmpty ? "输入文本" : "编辑文本"

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))

        textView.font = UIFont.systemFont(ofSize: 16)
        textView.text = initialText
        textView.backgroundColor = .cardBackground
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: compatSafeAreaTop, constant: 16),
            textView.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if initialText.isEmpty {
            textView.becomeFirstResponder()
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showAlert(title: "提示", message: "请输入文本内容")
            return
        }
        onSave?(text)
        dismiss(animated: true)
    }
}
