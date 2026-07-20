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
        return 5
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
        } else if indexPath.row == 1 {
            cell.textLabel?.text = "🎯 词语闯关"
            let totalLevels = WrongAnswerBookManager.shared.totalLevelsCompleted
            let costCoins = DeveloperSettingsManager.shared.effectiveQuizCostCoins
            cell.detailTextLabel?.text = totalLevels > 0 ? "已闯 \(totalLevels) 关 (每次消耗\(costCoins)金币)" : "开始挑战，巩固错题 (每次消耗\(costCoins)金币)"
        } else if indexPath.row == 2 {
            cell.textLabel?.text = "📊 闯关历史"
            let historyCount = WrongAnswerBookManager.shared.quizProgress.sessionHistory.count
            cell.detailTextLabel?.text = historyCount > 0 ? "共 \(historyCount) 次闯关记录" : "查看闯关成绩和金币记录"
        } else if indexPath.row == 3 {
            cell.textLabel?.text = "汉字拼图"
            let costCoins = DeveloperSettingsManager.shared.effectiveIdiomChainCostCoins
            cell.detailTextLabel?.text = "还原打乱的汉字顺序，消耗\(costCoins)金币"
        } else {
            cell.textLabel?.text = "汉字消消乐"
            let costCoins = DeveloperSettingsManager.shared.effectiveCharacterMatchCostCoins
            cell.detailTextLabel?.text = "翻牌配对汉字与拼音，消耗\(costCoins)金币"
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
        } else if indexPath.row == 1 {
            // 词语闯关 - check coins first, then confirm
            startQuizWithCoinCheck()
        } else if indexPath.row == 2 {
            // 闯关历史
            let historyVC = QuizHistoryViewController()
            navigationController?.pushViewController(historyVC, animated: true)
        } else if indexPath.row == 3 {
            // 汉字拼图
            startGameWithCoinCheck(gameName: "汉字拼图", costCoins: DeveloperSettingsManager.shared.effectiveIdiomChainCostCoins) { [weak self] in
                let vc = CharacterScrambleViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        } else {
            // 汉字消消乐
            startGameWithCoinCheck(gameName: "汉字消消乐", costCoins: DeveloperSettingsManager.shared.effectiveCharacterMatchCostCoins) { [weak self] in
                let vc = CharacterMatchViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            }
        }
    }

    /// Generic coin-check and confirmation flow for mini-games.
    private func startGameWithCoinCheck(gameName: String, costCoins: Int, onStart: @escaping () -> Void) {
        let currentCoins = RewardManager.shared.coins

        guard currentCoins >= costCoins else {
            let alert = UIAlertController(
                title: "金币不足",
                message: "\(gameName)需要消耗\(costCoins)金币，你当前有\(currentCoins)金币。请先完成阅读练习获取金币。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        let confirmAlert = UIAlertController(
            title: "开始\(gameName)",
            message: "本次游戏将消耗\(costCoins)金币。\n当前金币：\(currentCoins)\n确认开始吗？",
            preferredStyle: .alert
        )
        confirmAlert.addAction(UIAlertAction(title: "取消", style: .cancel))
        confirmAlert.addAction(UIAlertAction(title: "确认开始 (-\(costCoins)💰)", style: .default) { [weak self] _ in
            guard RewardManager.shared.spendCoins(costCoins) else { return }
            onStart()
        })
        present(confirmAlert, animated: true)
    }

    /// Checks if user has enough coins, then shows confirmation dialog before starting quiz.
    private func startQuizWithCoinCheck() {
        let currentCoins = RewardManager.shared.coins
        let costCoins = DeveloperSettingsManager.shared.effectiveQuizCostCoins
        let rewardCoins = DeveloperSettingsManager.shared.effectiveQuizRewardCoins

        // Check if user has enough coins
        guard currentCoins >= costCoins else {
            let alert = UIAlertController(
                title: "金币不足",
                message: "闯关需要消耗\(costCoins)金币，你当前有\(currentCoins)金币。请先完成阅读练习获取金币。",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }

        // Show confirmation dialog
        let confirmAlert = UIAlertController(
            title: "开始闯关",
            message: "本次闯关将消耗\(costCoins)金币。\n90分以上：完全胜利，获得\(rewardCoins)金币\n60分以上：成功，进入下一关\n60分以下：失败，无法进入下一关\n\n当前金币：\(currentCoins)\n确认开始吗？",
            preferredStyle: .alert
        )
        confirmAlert.addAction(UIAlertAction(title: "取消", style: .cancel))
        confirmAlert.addAction(UIAlertAction(title: "确认开始 (-\(costCoins)💰)", style: .default) { [weak self] _ in
            self?.proceedToQuiz()
        })
        present(confirmAlert, animated: true)
    }

    /// Deducts coins and starts the quiz.
    private func proceedToQuiz() {
        let costCoins = DeveloperSettingsManager.shared.effectiveQuizCostCoins
        // Deduct coins
        RewardManager.shared.spendCoins(costCoins)

        // Sync and start quiz
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
