import UIKit

// MARK: - Task Picker View Controller
/// A table view controller that allows the user to select multiple reading tasks.
/// Used for import/export operations.
final class TaskPickerViewController: UIViewController {

    // MARK: - Types

    /// Callback when user confirms selection.
    typealias SelectionHandler = ([ReadingTask]) -> Void

    // MARK: - Properties

    private let selectionHandler: SelectionHandler
    private let titleText: String
    private let confirmButtonTitle: String

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var tasks: [ReadingTask] = []
    private var selectedIndices = Set<Int>()

    // MARK: - Initialization

    /// - Parameters:
    ///   - title: Navigation bar title.
    ///   - confirmButtonTitle: Title for the confirm button.
    ///   - handler: Called with the selected tasks when user taps confirm.
    init(title: String, confirmButtonTitle: String = "确认", handler: @escaping SelectionHandler) {
        self.titleText = title
        self.confirmButtonTitle = confirmButtonTitle
        self.selectionHandler = handler
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        reloadData()
    }

    // MARK: - UI Setup

    private func setupUI() {
        title = titleText
        view.backgroundColor = .background

        // Confirm button on the right
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: confirmButtonTitle,
            style: .done,
            target: self,
            action: #selector(confirmTapped)
        )
        // Back button is automatically provided by the navigation controller.

        // Table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TaskPickerCell")
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 56
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func reloadData() {
        tasks = TaskManager.shared.tasks
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func confirmTapped() {
        let selected = selectedIndices.sorted().compactMap { index -> ReadingTask? in
            guard index < tasks.count else { return nil }
            return tasks[index]
        }
        guard !selected.isEmpty else {
            showAlert(title: "提示", message: "请至少选择一个阅读任务")
            return
        }
        selectionHandler(selected)
    }
}

// MARK: - UITableViewDataSource
extension TaskPickerViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tasks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TaskPickerCell", for: indexPath)
        let task = tasks[indexPath.row]
        let isSelected = selectedIndices.contains(indexPath.row)

        // Build display text
        let builtInMark = task.isBuiltIn ? " 📌" : ""
        cell.textLabel?.text = "\(task.title)\(builtInMark)"
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.text = task.detailDescription.isEmpty
            ? "\(task.expectedTexts.count) 段文本"
            : task.detailDescription
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
        cell.detailTextLabel?.textColor = .textSecondary
        cell.backgroundColor = .cardBackground
        cell.selectionStyle = .none

        // Green checkmark on the right when selected
        if isSelected {
            let checkmark = UILabel()
            checkmark.text = "✓"
            checkmark.font = UIFont.boldSystemFont(ofSize: 20)
            checkmark.textColor = .successGreen
            checkmark.sizeToFit()
            cell.accessoryView = checkmark
        } else {
            cell.accessoryView = nil
        }

        return cell
    }
}

// MARK: - UITableViewDelegate
extension TaskPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        if selectedIndices.contains(indexPath.row) {
            selectedIndices.remove(indexPath.row)
        } else {
            selectedIndices.insert(indexPath.row)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
    }
}
