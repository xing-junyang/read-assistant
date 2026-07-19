import UIKit

// MARK: - Word Challenge Menu View Controller
/// Menu page showing two items: 错题本 (Wrong Answer Book) and 词语闯关 (Word Challenge).
/// Similar in style to SettingsViewController.
final class WordChallengeMenuViewController: UIViewController {

    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let headerView = UIView()
    private let coinLabel = UILabel()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateCoinLabel()
        tableView.reloadData()
    }

    // MARK: - UI Setup
    private func setupUI() {
        title = "学习工具"
        view.backgroundColor = .background

        navigationItem.backBarButtonItem = UIBarButtonItem(title: "返回", style: .plain, target: nil, action: nil)

        // Header with coin display (frame-based for reliable tableHeaderView sizing)
        headerView.backgroundColor = .cardBackground
        headerView.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 60)

        coinLabel.frame = CGRect(x: 16, y: 12, width: headerView.bounds.width - 32, height: 36)
        coinLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        coinLabel.textColor = .accent
        coinLabel.textAlignment = .center
        coinLabel.autoresizingMask = [.flexibleWidth]
        headerView.addSubview(coinLabel)

        // TableView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        // No cell registration needed - we create cells manually in cellForRowAt
        tableView.tableHeaderView = headerView
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func updateCoinLabel() {
        let coins = RewardManager.shared.coins
        coinLabel.text = "💰 \(coins) 金币"
    }
}

// MARK: - UITableViewDataSource
extension WordChallengeMenuViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell: UITableViewCell
        if let dequeued = tableView.dequeueReusableCell(withIdentifier: "MenuCell") {
            cell = dequeued
        } else {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "MenuCell")
        }
        cell.backgroundColor = .cardBackground
        cell.accessoryType = .disclosureIndicator
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 13)
        cell.detailTextLabel?.textColor = .textSecondary

        if indexPath.row == 0 {
            cell.textLabel?.text = "📝 错题本"
            let count = WrongAnswerBookManager.shared.wrongAnswers.count
            cell.detailTextLabel?.text = count > 0 ? "已收集 \(count) 个错题" : "查看读错和遗漏的字词"
        } else {
            cell.textLabel?.text = "🎯 词语闯关"
            let totalLevels = WrongAnswerBookManager.shared.totalLevelsCompleted
            cell.detailTextLabel?.text = totalLevels > 0 ? "已闯 \(totalLevels) 关" : "开始挑战，巩固错题"
        }

        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "功能"
    }
}

// MARK: - UITableViewDelegate
extension WordChallengeMenuViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.row == 0 {
            // 错题本 - sync first, then show list
            let loadingAlert = UIAlertController(title: "更新中...", message: "正在从阅读历史同步错题", preferredStyle: .alert)
            present(loadingAlert, animated: true)

            WrongAnswerBookManager.shared.syncWrongAnswers()
            WrongAnswerBookManager.shared.waitForSync { [weak self] in
                loadingAlert.dismiss(animated: true) {
                    let vc = WrongAnswerBookViewController()
                    self?.navigationController?.pushViewController(vc, animated: true)
                }
            }
        } else {
            // 词语闯关 - sync first, then start quiz
            let loadingAlert = UIAlertController(title: "准备中...", message: "正在同步错题数据", preferredStyle: .alert)
            present(loadingAlert, animated: true)

            WrongAnswerBookManager.shared.syncWrongAnswers()
            WrongAnswerBookManager.shared.waitForSync { [weak self] in
                loadingAlert.dismiss(animated: true) {
                    guard let self = self else { return }
                    let manager = WrongAnswerBookManager.shared
                    guard let questions = manager.generateQuizLevel() else {
                        let alert = UIAlertController(
                            title: "无法开始",
                            message: "错题本中至少需要4个字词才能开始闯关。请先完成一些阅读练习。",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "确定", style: .default))
                        self.present(alert, animated: true)
                        return
                    }

                    // Create quiz session data
                    let levelNumber = manager.totalLevelsCompleted + 1
                    let quizData = questions.map { q -> QuizQuestionData in
                        return QuizQuestionData(
                            correctAnswer: q.correctAnswer,
                            options: q.options,
                            correctIndex: q.correctIndex,
                            questionType: q.questionType.rawValue,
                            sourceItemID: q.sourceItem.id
                        )
                    }
                    let session = QuizSession(levelNumber: levelNumber, questions: quizData)

                    let quizVC = QuizViewController(quizSession: session, questions: questions)
                    self.navigationController?.pushViewController(quizVC, animated: true)
                }
            }
        }
    }
}
