import UIKit

// MARK: - Task List View Controller
/// Main view controller displaying all reading tasks.
/// Supports add, delete, duplicate, reorder, and search.
final class TaskListViewController: UIViewController {

    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = UIView()
    private let heartsBar = UIView()
    private let heartsIconLabel = UILabel()
    private let heartsCountLabel = UILabel()
    private let heartsTimerLabel = UILabel()
    private var heartsRefreshTimer: Timer?

    private var tasks: [ReadingTask] {
        return TaskManager.shared.tasks
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        setupHeartsBar()
        setupTableView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateEmptyState()
        refreshHeartsBar()
        startHeartsTimer()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopHeartsTimer()
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
            tableView.topAnchor.constraint(equalTo: heartsBar.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
    
    // MARK: - Hearts Bar
    
    private func setupHeartsBar() {
        heartsBar.backgroundColor = .cardBackground
        heartsBar.layer.shadowColor = UIColor.black.cgColor
        heartsBar.layer.shadowOpacity = 0.05
        heartsBar.layer.shadowOffset = CGSize(width: 0, height: 1)
        heartsBar.layer.shadowRadius = 2
        heartsBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(heartsBar)
        
        heartsIconLabel.font = UIFont.systemFont(ofSize: 14)
        heartsIconLabel.text = "❤️"
        heartsIconLabel.translatesAutoresizingMaskIntoConstraints = false
        heartsBar.addSubview(heartsIconLabel)
        
        heartsCountLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        heartsCountLabel.textColor = .textPrimary
        heartsCountLabel.translatesAutoresizingMaskIntoConstraints = false
        heartsBar.addSubview(heartsCountLabel)
        
        heartsTimerLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        heartsTimerLabel.textColor = .textTertiary
        heartsTimerLabel.translatesAutoresizingMaskIntoConstraints = false
        heartsBar.addSubview(heartsTimerLabel)
        
        NSLayoutConstraint.activate([
            heartsBar.topAnchor.constraint(equalTo: compatSafeAreaTop),
            heartsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heartsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heartsBar.heightAnchor.constraint(equalToConstant: 44),
            
            heartsIconLabel.leadingAnchor.constraint(equalTo: heartsBar.leadingAnchor, constant: 16),
            heartsIconLabel.centerYAnchor.constraint(equalTo: heartsBar.centerYAnchor),
            
            heartsCountLabel.leadingAnchor.constraint(equalTo: heartsIconLabel.trailingAnchor, constant: 6),
            heartsCountLabel.centerYAnchor.constraint(equalTo: heartsBar.centerYAnchor),
            
            heartsTimerLabel.trailingAnchor.constraint(equalTo: heartsBar.trailingAnchor, constant: -16),
            heartsTimerLabel.centerYAnchor.constraint(equalTo: heartsBar.centerYAnchor)
        ])
    }
    
    private func refreshHeartsBar() {
        let heartsManager = HeartsManager.shared
        let hearts = heartsManager.hearts
        let maxHearts = heartsManager.maxHearts
        
        if heartsManager.unlimitedHearts {
            heartsCountLabel.text = "∞"
            heartsCountLabel.textColor = .accent
            heartsTimerLabel.text = "无限模式"
            heartsTimerLabel.textColor = .accent
        } else {
            heartsCountLabel.text = "\(hearts)/\(maxHearts)"
            heartsCountLabel.textColor = hearts > 0 ? .textPrimary : .errorRed
            
            if hearts >= maxHearts {
                heartsTimerLabel.text = "⏱ 已满"
                heartsTimerLabel.textColor = .textPrimary
            } else {
                let remaining = heartsManager.secondsUntilNextHeart
                let minutes = Int(remaining) / 60
                let seconds = Int(remaining) % 60
                heartsTimerLabel.text = "⏱ \(minutes):\(String(format: "%02d", seconds))"
                heartsTimerLabel.textColor = .textPrimary
            }
        }
    }
    
    private func startHeartsTimer() {
        stopHeartsTimer()
        heartsRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshHeartsBar()
        }
    }
    
    private func stopHeartsTimer() {
        heartsRefreshTimer?.invalidate()
        heartsRefreshTimer = nil
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
