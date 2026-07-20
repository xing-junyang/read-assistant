import UIKit

// MARK: - Quiz History View Controller
/// Displays the history of all quiz challenge sessions with scores, errors, and coin records.
final class QuizHistoryViewController: UIViewController {

    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = UIView()
    private var sessions: [QuizSession] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }

    // MARK: - Data Loading
    private func loadData() {
        sessions = WrongAnswerBookManager.shared.quizProgress.sessionHistory.reversed()
        tableView.reloadData()
        updateEmptyState()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "闯关历史"

        // Summary header
        let headerView = createSummaryHeader()
        headerView.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 80)

        // TableView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        tableView.tableHeaderView = headerView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Empty state
        setupEmptyState()
    }

    private func createSummaryHeader() -> UIView {
        let container = UIView()
        container.backgroundColor = .cardBackground

        let totalSessions = sessions.count
        let totalPassed = sessions.filter { $0.resultTier != .failure }.count
        let totalCoinsEarned = sessions.reduce(0) { $0 + max(0, $1.coinsEarned) }
        let costPerSession = DeveloperSettingsManager.shared.effectiveQuizCostCoins
        let totalCoinsSpent = sessions.count * costPerSession

        let label = UILabel()
        label.frame = CGRect(x: 16, y: 10, width: container.bounds.width > 0 ? container.bounds.width - 32 : UIScreen.main.bounds.width - 32, height: 60)
        label.numberOfLines = 3
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = .textSecondary
        label.textAlignment = .center

        let summaryText = "共闯关 \(totalSessions) 次 | 通过 \(totalPassed) 次 | 赚取 \(totalCoinsEarned)💰 | 消耗 \(totalCoinsSpent)💰"
        label.text = summaryText
        container.addSubview(label)

        return container
    }

    private func setupEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        view.addSubview(emptyStateView)

        let iconLabel = UILabel()
        iconLabel.text = "📊"
        iconLabel.font = UIFont.systemFont(ofSize: 48)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(iconLabel)

        let messageLabel = UILabel()
        messageLabel.text = "还没有闯关记录\n完成词语闯关后，成绩和金币记录会显示在这里"
        messageLabel.font = UIFont.systemFont(ofSize: 15)
        messageLabel.textColor = .textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            iconLabel.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            iconLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),

            messageLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor, constant: -32),
            messageLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }

    private func updateEmptyState() {
        emptyStateView.isHidden = !sessions.isEmpty
        tableView.isHidden = sessions.isEmpty
    }
}

// MARK: - UITableViewDataSource
extension QuizHistoryViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sessions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        if let dequeued = tableView.dequeueReusableCell(withIdentifier: "HistoryCell") {
            cell = dequeued
        } else {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "HistoryCell")
        }
        cell.backgroundColor = .cardBackground
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
        cell.detailTextLabel?.textColor = .textSecondary
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = .none
        cell.selectionStyle = .none

        let session = sessions[indexPath.row]
        let score = session.score
        let total = session.totalQuestions
        let percentage = total > 0 ? Int(Double(score) / Double(total) * 100) : 0

        // Format date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM-dd HH:mm"
        let dateStr = dateFormatter.string(from: session.endTime ?? session.startTime)

        // Tier icon and label
        let tierIcon: String
        let tierLabel: String
        switch session.resultTier {
        case .completeVictory:
            tierIcon = "🏆"
            tierLabel = "完全胜利"
        case .success:
            tierIcon = "✅"
            tierLabel = "成功"
        case .failure:
            tierIcon = "❌"
            tierLabel = "失败"
        }

        // Wrong answers count
        let wrongCount = session.totalQuestions - session.score

        cell.textLabel?.text = "\(tierIcon) 第\(session.levelNumber)关 · \(tierLabel) · \(score)/\(total) (\(percentage)%)"

        var details: [String] = [dateStr]
        if wrongCount > 0 {
            details.append("错\(wrongCount)题")
        }
        if session.coinsEarned > 0 {
            details.append("获得 +\(session.coinsEarned)💰")
        } else if session.coinsEarned < 0 {
            details.append("消耗 1💰")
        } else {
            details.append("无金币变动")
        }
        cell.detailTextLabel?.text = details.joined(separator: " · ")

        return cell
    }
}

// MARK: - UITableViewDelegate
extension QuizHistoryViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
