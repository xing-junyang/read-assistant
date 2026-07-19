import UIKit

// MARK: - Task List View Controller
/// Main view controller displaying all reading tasks.
/// Supports add, delete, duplicate, reorder, and search.
final class TaskListViewController: UIViewController {

    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = UIView()

    private var tasks: [ReadingTask] {
        return TaskManager.shared.tasks
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        setupTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "阅读任务"

        // Empty state
        emptyStateView.isHidden = true
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateView)

        let emptyIcon = UILabel()
        emptyIcon.text = "📖"
        emptyIcon.font = UIFont.systemFont(ofSize: 48)
        emptyIcon.textAlignment = .center
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(emptyIcon)

        let emptyLabel = UILabel()
        emptyLabel.text = "暂无阅读任务\n点击右上角 + 创建新任务"
        emptyLabel.font = UIFont.systemFont(ofSize: 16)
        emptyLabel.textColor = .textSecondary
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),

            emptyIcon.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyIcon.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),

            emptyLabel.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 16),
            emptyLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            emptyLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }

    private func setupNavigationBar() {
        // Add button
        let addButton = UIBarButtonItem(title: "添加", style: .plain, target: self, action: #selector(addTaskTapped))
        navigationItem.rightBarButtonItem = addButton

        // Edit button
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "编辑", style: .plain, target: self, action: #selector(toggleEdit))
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(TaskCell.self, forCellReuseIdentifier: TaskCell.reuseIdentifier)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .background
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func updateEmptyState() {
        emptyStateView.isHidden = !tasks.isEmpty
        tableView.isHidden = tasks.isEmpty
    }

    // MARK: - Actions

    @objc private func addTaskTapped() {
        showInputAlert(title: "新建阅读任务", placeholder: "请输入任务名称") { [weak self] name in
            let task = ReadingTask(title: name)
            TaskManager.shared.addTask(task)
            self?.tableView.reloadData()
            self?.updateEmptyState()
        }
    }

    // MARK: - Editing
    @objc private func toggleEdit() {
        let newEditing = !isEditing
        setEditing(newEditing, animated: true)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
        navigationItem.leftBarButtonItem?.title = editing ? "完成" : "编辑"
    }
}

// MARK: - UITableViewDataSource
extension TaskListViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tasks.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: TaskCell.reuseIdentifier, for: indexPath) as? TaskCell else {
            return UITableViewCell()
        }
        cell.configure(with: tasks[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let task = tasks[indexPath.row]
        return !task.isBuiltIn
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        let task = tasks[indexPath.row]
        return !task.isBuiltIn
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        TaskManager.shared.moveTask(from: sourceIndexPath.row, to: destinationIndexPath.row)
    }
}

// MARK: - UITableViewDelegate
extension TaskListViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let task = tasks[indexPath.row]
        let detailVC = TaskDetailViewController(taskId: task.id)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    // MARK: - Swipe Actions (iOS 10 compatible)
    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        let task = tasks[indexPath.row]
        var actions: [UITableViewRowAction] = []

        if !task.isBuiltIn {
            let deleteAction = UITableViewRowAction(style: .destructive, title: "删除") { [weak self] _, index in
                self?.deleteTask(at: index)
            }
            actions.append(deleteAction)

            let duplicateAction = UITableViewRowAction(style: .normal, title: "复制") { [weak self] _, index in
                self?.duplicateTask(at: index)
            }
            duplicateAction.backgroundColor = .primary
            actions.append(duplicateAction)
        }

        let editAction = UITableViewRowAction(style: .normal, title: "编辑") { [weak self] _, index in
            self?.editTask(at: index)
        }
        editAction.backgroundColor = .accent
        actions.append(editAction)

        return actions.isEmpty ? nil : actions
    }

    private func deleteTask(at indexPath: IndexPath) {
        let task = tasks[indexPath.row]
        guard !task.isBuiltIn else { return }
        showConfirm(title: "删除任务", message: "确定要删除「\(task.title)」吗？此操作不可撤销。") { [weak self] in
            TaskManager.shared.removeTask(withId: task.id)
            self?.tableView.reloadData()
            self?.updateEmptyState()
        }
    }

    private func duplicateTask(at indexPath: IndexPath) {
        let task = tasks[indexPath.row]
        guard !task.isBuiltIn else { return }
        _ = TaskManager.shared.duplicateTask(withId: task.id)
        tableView.reloadData()
        updateEmptyState()
    }

    private func editTask(at indexPath: IndexPath) {
        let task = tasks[indexPath.row]
        showInputAlert(title: "编辑任务名称", initialText: task.title) { [weak self] newName in
            task.title = newName
            TaskManager.shared.updateTask(task)
            self?.tableView.reloadData()
        }
    }
}
