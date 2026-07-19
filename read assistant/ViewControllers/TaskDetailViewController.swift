import UIKit
import AVFoundation

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

    // Audio playback bar
    private let playbackBar = PlaybackBarView()
    private var currentlyPlayingSessionId: String?
    private var playbackBarBottomConstraint: NSLayoutConstraint?

    // 3D Touch previewing (iOS 10+)
    private var previewingContext: UIViewControllerPreviewing?

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
        setupPlaybackBar()
        registerFor3DTouch()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateStartButton()
        updateNavigationBar()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = task?.title ?? "任务详情"
    }

    private func updateNavigationBar() {
        guard let task = task else { return }
        if task.isBuiltIn {
            navigationItem.rightBarButtonItem = nil
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "添加阅读文段",
                style: .plain,
                target: self,
                action: #selector(addExpectedText)
            )
        }
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ExpectedTextCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "OverviewCell")
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

    private func setupPlaybackBar() {
        playbackBar.delegate = self
        playbackBar.isHidden = true
        playbackBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playbackBar)

        let bottomConstraint = playbackBar.bottomAnchor.constraint(equalTo: startReadingButton.topAnchor, constant: -8)
        playbackBarBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            playbackBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            playbackBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            playbackBar.heightAnchor.constraint(equalToConstant: 64),
            bottomConstraint
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
        let hasTexts = !task.expectedTexts.isEmpty
        startReadingButton.isEnabled = hasTexts
        startReadingButton.alpha = hasTexts ? 1.0 : 0.5
        if hasTexts {
            startReadingButton.setTitle("开始阅读", for: .normal)
            startReadingButton.backgroundColor = .primary
        } else {
            startReadingButton.setTitle("暂无文本", for: .normal)
            startReadingButton.backgroundColor = .textSecondary
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        playbackBar.stopPlayback()
        currentlyPlayingSessionId = nil
        playbackBar.isHidden = true
    }

    // MARK: - Audio Playback

    /// Shows the playback bar and starts playing the audio for a session.
    private func startPlayback(for session: ReadingSession) {
        guard let audioPath = session.audioFilePath,
              AudioRecordingManager.audioFileExists(at: audioPath) else {
            showAlert(title: "无法播放", message: "录音文件不存在")
            return
        }

        do {
            let url = URL(fileURLWithPath: audioPath)
            try playbackBar.loadAudio(url: url)
            playbackBar.play()
            currentlyPlayingSessionId = session.id
            showPlaybackBar()
            tableView.reloadData()
        } catch {
            showAlert(title: "播放失败", message: error.localizedDescription)
        }
    }

    private func stopPlayback() {
        playbackBar.stopPlayback()
        currentlyPlayingSessionId = nil
        hidePlaybackBar()
        tableView.reloadData()
    }

    private func showPlaybackBar() {
        playbackBar.isHidden = false
        playbackBar.alpha = 0
        UIView.animate(withDuration: 0.25) {
            self.playbackBar.alpha = 1.0
            // Adjust table view bottom inset so content isn't hidden behind playback bar
            self.tableView.contentInset.bottom = 72
        }
    }

    private func hidePlaybackBar() {
        UIView.animate(withDuration: 0.25, animations: {
            self.playbackBar.alpha = 0
            self.tableView.contentInset.bottom = 0
        }) { _ in
            if self.currentlyPlayingSessionId == nil {
                self.playbackBar.isHidden = true
            }
        }
    }

    @objc private func playButtonTapped(_ sender: UIButton) {
        guard let task = task, sender.tag < task.sessions.count else { return }
        let session = task.sessions[sender.tag]

        // If already playing this session, toggle play/pause
        if currentlyPlayingSessionId == session.id {
            if playbackBar.isPlaying {
                playbackBar.pause()
            } else {
                playbackBar.play()
            }
            tableView.reloadData()
            return
        }

        // Stop any existing playback and start new one
        stopPlayback()
        startPlayback(for: session)
    }

    // MARK: - Actions

    @objc private func addExpectedText() {
        showActionSheet(title: "添加阅读文本", actions: [
            ("手动输入", .default, { [weak self] in self?.showManualInput() }),
            ("拍照识别", .default, { [weak self] in self?.showOCRScanner() })
        ])
    }

    private func showManualInput() {
        // Present a multi-line text input
        let inputVC = TextInputViewController()
        inputVC.onSave = { [weak self] text in
            guard let self = self, let task = self.task else { return }
            self.appendExpectedText(text, to: task)
            TaskManager.shared.updateTask(task)
            self.tableView.reloadData()
            self.updateStartButton()
        }
        let nav = UINavigationController(rootViewController: inputVC)
        present(nav, animated: true)
    }

    private func showOCRScanner() {
        let ocrVC = OCRScanViewController()

        // API key is now configured via DeveloperSettingsManager at init time.
        // No need to override here — BailianOCRService.init() picks up the effective key automatically.

        ocrVC.onTextRecognized = { [weak self] text in
            guard let self = self, let task = self.task else { return }
            self.appendExpectedText(text, to: task)
            TaskManager.shared.updateTask(task)
            self.tableView.reloadData()
            self.updateStartButton()
        }
        let nav = UINavigationController(rootViewController: ocrVC)
        present(nav, animated: true)
    }

    /// Appends expected text to the task, respecting the auto-split-by-newline setting.
    private func appendExpectedText(_ text: String, to task: ReadingTask) {
        let autoSplit = UserDefaults.standard.object(forKey: "auto_split_by_newline_enabled") as? Bool ?? true
        if autoSplit {
            let paragraphs = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for paragraph in paragraphs {
                task.expectedTexts.append(paragraph)
            }
        } else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                task.expectedTexts.append(trimmed)
            }
        }
    }

    @objc private func startReadingTapped() {
        guard let task = task, !task.expectedTexts.isEmpty else { return }
        let readingVC = ReadingViewController(taskId: task.id)
        navigationController?.pushViewController(readingVC, animated: true)
    }

    // MARK: - 3D Touch Previewing (iOS 10+)

    /// Registers the table view for 3D Touch peek/pop previews.
    /// Gracefully skips registration on devices without 3D Touch support.
    private func registerFor3DTouch() {
        guard traitCollection.forceTouchCapability == .available else { return }
        previewingContext = registerForPreviewing(with: self, sourceView: tableView)
    }
}

// MARK: - UITableViewDataSource
extension TaskDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let task = task else { return 0 }
        switch section {
        case 0: return 1 // Overview
        case 1: return task.expectedTexts.isEmpty ? 1 : task.expectedTexts.count
        case 2: return task.sessions.count
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "概览"
        case 1: return "期望阅读文本"
        case 2: return "历史阅读记录"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let task = task else { return UITableViewCell() }

        switch indexPath.section {
        case 0:
            // Overview cell with circular indicators
            let cell = tableView.dequeueReusableCell(withIdentifier: "OverviewCell", for: indexPath)
            cell.selectionStyle = .none
            cell.accessoryType = .none

            // Remove previous overview subviews (tagged 1000-1999)
            cell.contentView.subviews.filter { (1000...1999).contains($0.tag) }.forEach { $0.removeFromSuperview() }

            let totalParagraphs = task.expectedTexts.count
            let readIndices = Set(task.sessions.map { $0.expectedTextIndex })
            let readCount = task.expectedTexts.indices.filter { readIndices.contains($0) }.count
            let completionRate = totalParagraphs > 0 ? Double(readCount) / Double(totalParagraphs) : 0.0
            let totalScore = computeTotalScore(for: task)
            let hasData = totalParagraphs > 0 && readCount > 0

            // Container stack for the two circles
            let containerStack = UIStackView()
            containerStack.axis = .horizontal
            containerStack.alignment = .center
            containerStack.distribution = .fill
            containerStack.spacing = 24
            containerStack.tag = 1000
            containerStack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(containerStack)

            // --- Left: Completion Rate Ring ---
            let ringSize: CGFloat = 90
            let ringWidth: CGFloat = 8

            let completionContainer = UIView()
            completionContainer.tag = 1001
            completionContainer.translatesAutoresizingMaskIntoConstraints = false

            // --- Ring view: exactly ringSize × ringSize, so label centers perfectly ---
            let ringView = UIView()
            ringView.backgroundColor = .clear
            ringView.tag = 1005
            ringView.translatesAutoresizingMaskIntoConstraints = false
            completionContainer.addSubview(ringView)

            // Track ring (gray background)
            let trackLayer = CAShapeLayer()
            let center = CGPoint(x: ringSize / 2, y: ringSize / 2)
            let radius = (ringSize - ringWidth) / 2
            let ringPath = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: -CGFloat.pi / 2,
                endAngle: CGFloat.pi * 1.5,
                clockwise: true
            )
            trackLayer.path = ringPath.cgPath
            trackLayer.fillColor = UIColor.clear.cgColor
            trackLayer.strokeColor = UIColor.separator.cgColor
            trackLayer.lineWidth = ringWidth
            trackLayer.lineCap = .round
            ringView.layer.addSublayer(trackLayer)

            // Progress ring (colored)
            let progressLayer = CAShapeLayer()
            progressLayer.path = ringPath.cgPath
            progressLayer.fillColor = UIColor.clear.cgColor
            progressLayer.strokeColor = (completionRate >= 1.0 ? UIColor.successGreen : UIColor.primary).cgColor
            progressLayer.lineWidth = ringWidth
            progressLayer.lineCap = .round
            progressLayer.strokeEnd = totalParagraphs > 0 ? CGFloat(completionRate) : 0
            ringView.layer.addSublayer(progressLayer)

            // Center label: completion percentage
            let rateLabel = UILabel()
            rateLabel.text = totalParagraphs > 0 ? "\(Int(completionRate * 100))%" : "--"
            rateLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
            rateLabel.textColor = .textPrimary
            rateLabel.textAlignment = .center
            rateLabel.tag = 1002
            rateLabel.translatesAutoresizingMaskIntoConstraints = false
            ringView.addSubview(rateLabel)

            // Caption below ring
            let rateCaption = UILabel()
            rateCaption.text = totalParagraphs > 0 ? "\(readCount)/\(totalParagraphs) 段" : "完成率"
            rateCaption.font = UIFont.systemFont(ofSize: 11)
            rateCaption.textColor = .textSecondary
            rateCaption.textAlignment = .center
            rateCaption.tag = 1003
            rateCaption.translatesAutoresizingMaskIntoConstraints = false
            completionContainer.addSubview(rateCaption)

            // --- Right: Total Score Circle ---
            let scoreCircleSize: CGFloat = 80

            let scoreContainer = UIView()
            scoreContainer.tag = 1010
            scoreContainer.translatesAutoresizingMaskIntoConstraints = false

            let scoreCircle = UIView()
            scoreCircle.layer.cornerRadius = scoreCircleSize / 2
            scoreCircle.backgroundColor = scoreCircleColor(score: totalScore, hasData: hasData)
            scoreCircle.tag = 1011
            scoreCircle.translatesAutoresizingMaskIntoConstraints = false
            scoreContainer.addSubview(scoreCircle)

            let scoreNumberLabel = UILabel()
            scoreNumberLabel.text = hasData ? "\(Int(totalScore))" : "--"
            scoreNumberLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold)
            scoreNumberLabel.textColor = .white
            scoreNumberLabel.textAlignment = .center
            scoreNumberLabel.tag = 1012
            scoreNumberLabel.translatesAutoresizingMaskIntoConstraints = false
            scoreCircle.addSubview(scoreNumberLabel)

            let unitLabel = UILabel()
            unitLabel.text = "分"
            unitLabel.font = UIFont.systemFont(ofSize: 11)
            unitLabel.textColor = UIColor.white.withAlphaComponent(0.8)
            unitLabel.textAlignment = .center
            unitLabel.tag = 1013
            unitLabel.translatesAutoresizingMaskIntoConstraints = false
            scoreCircle.addSubview(unitLabel)

            let scoreCaption = UILabel()
            scoreCaption.text = "总得分"
            scoreCaption.font = UIFont.systemFont(ofSize: 11)
            scoreCaption.textColor = .textSecondary
            scoreCaption.textAlignment = .center
            scoreCaption.tag = 1014
            scoreCaption.translatesAutoresizingMaskIntoConstraints = false
            scoreContainer.addSubview(scoreCaption)

            // Add to stack
            containerStack.addArrangedSubview(completionContainer)
            containerStack.addArrangedSubview(scoreContainer)

            // Layout
            let containerHeight: CGFloat = ringSize + 26 // ring + caption spacing
            NSLayoutConstraint.activate([
                containerStack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 14),
                containerStack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -14),
                containerStack.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
                containerStack.widthAnchor.constraint(lessThanOrEqualTo: cell.contentView.widthAnchor, constant: -32),

                completionContainer.widthAnchor.constraint(equalToConstant: ringSize),
                completionContainer.heightAnchor.constraint(equalToConstant: containerHeight),

                ringView.topAnchor.constraint(equalTo: completionContainer.topAnchor),
                ringView.centerXAnchor.constraint(equalTo: completionContainer.centerXAnchor),
                ringView.widthAnchor.constraint(equalToConstant: ringSize),
                ringView.heightAnchor.constraint(equalToConstant: ringSize),

                rateLabel.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
                rateLabel.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),

                rateCaption.centerXAnchor.constraint(equalTo: completionContainer.centerXAnchor),
                rateCaption.topAnchor.constraint(equalTo: ringView.bottomAnchor, constant: 2),

                scoreContainer.widthAnchor.constraint(equalToConstant: scoreCircleSize),
                scoreContainer.heightAnchor.constraint(equalToConstant: containerHeight),

                scoreCircle.topAnchor.constraint(equalTo: scoreContainer.topAnchor, constant: (ringSize - scoreCircleSize) / 2),
                scoreCircle.centerXAnchor.constraint(equalTo: scoreContainer.centerXAnchor),
                scoreCircle.widthAnchor.constraint(equalToConstant: scoreCircleSize),
                scoreCircle.heightAnchor.constraint(equalToConstant: scoreCircleSize),

                scoreNumberLabel.centerXAnchor.constraint(equalTo: scoreCircle.centerXAnchor),
                scoreNumberLabel.centerYAnchor.constraint(equalTo: scoreCircle.centerYAnchor, constant: -6),

                unitLabel.topAnchor.constraint(equalTo: scoreNumberLabel.bottomAnchor, constant: -2),
                unitLabel.centerXAnchor.constraint(equalTo: scoreCircle.centerXAnchor),

                scoreCaption.centerXAnchor.constraint(equalTo: scoreContainer.centerXAnchor),
                scoreCaption.topAnchor.constraint(equalTo: scoreContainer.topAnchor, constant: ringSize + 2)
            ])

            return cell

        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ExpectedTextCell", for: indexPath)
            cell.selectionStyle = .none

            if task.expectedTexts.isEmpty {
                cell.textLabel?.text = "暂无文本，点击右上角 + 添加"
                cell.textLabel?.textColor = .textTertiary
                cell.accessoryType = .none
                cell.detailTextLabel?.text = nil
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

        case 2:
            let cell: UITableViewCell
            if let reused = tableView.dequeueReusableCell(withIdentifier: "HistoryCell") {
                cell = reused
            } else {
                cell = UITableViewCell(style: .subtitle, reuseIdentifier: "HistoryCell")
            }
            let session = task.sessions[indexPath.row]
            let textIndex = session.expectedTextIndex
            let preview = textIndex < task.expectedTexts.count ? task.expectedTexts[textIndex].truncated(40) : "未知文本"
            cell.textLabel?.text = "\(indexPath.row + 1). \(preview)"
            cell.textLabel?.numberOfLines = 1
            cell.textLabel?.textColor = .textPrimary

            // Build subtitle: score + playback indicator
            var subtitleParts: [String] = []
            if let result = session.result {
                subtitleParts.append("得分: \(Int(result.score))%")
            }
            let isCurrentSession = (currentlyPlayingSessionId == session.id)
            let isPlaying = isCurrentSession && playbackBar.isPlaying
            let hasAudio = session.audioFilePath != nil && AudioRecordingManager.audioFileExists(at: session.audioFilePath!)
            if isPlaying {
                subtitleParts.append("🔊 正在播放...")
            } else if hasAudio {
                subtitleParts.append("🎵 有录音")
            }
            cell.detailTextLabel?.text = subtitleParts.joined(separator: " | ")
            if let result = session.result {
                cell.detailTextLabel?.textColor = result.score >= 80 ? .successGreen : .textSecondary
            } else {
                cell.detailTextLabel?.textColor = .textSecondary
            }

            // Accessory: play/pause button if audio available, else disclosure indicator
            if hasAudio {
                let playButton = UIButton(type: .system)
                playButton.setTitle(isPlaying ? "⏸" : "▶", for: .normal)
                playButton.titleLabel?.font = UIFont.systemFont(ofSize: 18)
                playButton.tag = indexPath.row
                playButton.addTarget(self, action: #selector(playButtonTapped(_:)), for: .touchUpInside)
                playButton.sizeToFit()
                cell.accessoryView = playButton
            } else {
                cell.accessoryView = nil
                cell.accessoryType = session.result != nil ? .disclosureIndicator : .none
            }
            return cell

        default:
            return UITableViewCell()
        }
    }

    // MARK: - Score Computation
    /// Computes total score: for each expected text paragraph, find the highest
    /// historical score across all sessions. Average those highest scores.
    /// Unread paragraphs are excluded from the average.
    private func computeTotalScore(for task: ReadingTask) -> Double {
        guard !task.expectedTexts.isEmpty else { return 0.0 }

        var highestScores: [Double] = []
        for index in task.expectedTexts.indices {
            let sessionsForIndex = task.sessions.filter { $0.expectedTextIndex == index }
            let scores = sessionsForIndex.compactMap { $0.result?.score }
            if let maxScore = scores.max() {
                highestScores.append(maxScore)
            }
            // Unread paragraphs are not included
        }

        guard !highestScores.isEmpty else { return 0.0 }
        return highestScores.reduce(0.0, +) / Double(highestScores.count)
    }

    /// Returns the color for the score circle based on score value.
    private func scoreCircleColor(score: Double, hasData: Bool) -> UIColor {
        guard hasData else { return .textTertiary }
        if score >= 90 { return .successGreen }
        if score >= 70 { return .primary }
        if score >= 50 { return .warningOrange }
        return .errorRed
    }
}

// MARK: - UITableViewDelegate
extension TaskDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 {
            return 140 // Overview circles (ring + score circle + captions)
        }
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let task = task else { return }

        switch indexPath.section {
        case 0:
            // Overview - no action
            break
        case 1 where !task.expectedTexts.isEmpty && !task.isBuiltIn:
            // Edit expected text (only for user-created tasks)
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
        case 2:
            // View result (playback is handled by the play button)
            let session = task.sessions[indexPath.row]
            if let result = session.result {
                let resultVC = ResultViewController(result: result)
                navigationController?.pushViewController(resultVC, animated: true)
            }
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == 1 {
            guard let task = task else { return false }
            return !task.expectedTexts.isEmpty && !task.isBuiltIn
        }
        if indexPath.section == 2 {
            return true // Allow deleting history sessions
        }
        return false
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let task = task else { return }
            if indexPath.section == 1 {
                task.expectedTexts.remove(at: indexPath.row)
                TaskManager.shared.updateTask(task)
                tableView.reloadData()
                updateStartButton()
            } else if indexPath.section == 2 {
                let session = task.sessions[indexPath.row]
                // Stop playback if deleting the currently playing session
                if currentlyPlayingSessionId == session.id {
                    stopPlayback()
                }
                TaskManager.shared.removeSession(session, fromTaskId: task.id)
                tableView.reloadData()
            }
        }
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        if indexPath.section == 1 {
            guard let task = task, !task.isBuiltIn else { return nil }
            let deleteAction = UITableViewRowAction(style: .destructive, title: "删除") { [weak self] _, _ in
                guard let self = self, let task = self.task else { return }
                task.expectedTexts.remove(at: indexPath.row)
                TaskManager.shared.updateTask(task)
                self.tableView.reloadData()
                self.updateStartButton()
            }
            return [deleteAction]
        }

        if indexPath.section == 2 {
            let deleteAction = UITableViewRowAction(style: .destructive, title: "删除") { [weak self] _, _ in
                guard let self = self, let task = self.task else { return }
                let session = task.sessions[indexPath.row]
                // Stop playback if deleting the currently playing session
                if self.currentlyPlayingSessionId == session.id {
                    self.stopPlayback()
                }
                TaskManager.shared.removeSession(session, fromTaskId: task.id)
                self.tableView.reloadData()
            }
            return [deleteAction]
        }

        return nil
    }
}

// MARK: - PlaybackBarViewDelegate
extension TaskDetailViewController: PlaybackBarViewDelegate {
    func playbackBarViewDidFinishPlaying(_ view: PlaybackBarView) {
        // Playback completed — keep the bar visible but update cell buttons
        tableView.reloadData()
    }

    func playbackBarView(_ view: PlaybackBarView, didEncounterError error: Error) {
        showAlert(title: "播放错误", message: error.localizedDescription)
        stopPlayback()
    }
}

// MARK: - UIViewControllerPreviewingDelegate (3D Touch Peek & Pop)
extension TaskDetailViewController: UIViewControllerPreviewingDelegate {

    /// Called when the user begins a 3D Touch press.
    /// Returns a preview view controller for the cell under the touch location.
    func previewingContext(_ previewingContext: UIViewControllerPreviewing,
                           viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard let indexPath = tableView.indexPathForRow(at: location),
              let task = task else { return nil }

        // Set the source rect to the cell's frame so the untouched area blurs
        if let cell = tableView.cellForRow(at: indexPath) {
            previewingContext.sourceRect = cell.frame
        }

        switch indexPath.section {
        case 1 where !task.expectedTexts.isEmpty:
            // Preview: expected reading text
            let text = task.expectedTexts[indexPath.row]
            let content = PreviewViewController.PreviewContent.expectedText(
                text: text,
                index: indexPath.row,
                total: task.expectedTexts.count
            )
            let previewVC = PreviewViewController(content: content)

            // Set commit action: push to edit (user tasks) or show full text
            previewVC.onCommit = { [weak self] in
                guard let self = self, let task = self.task else { return }
                if task.isBuiltIn {
                    // Built-in tasks: just show the full text in a simple viewer
                    let fullTextVC = TextPreviewFullViewController(text: text, title: "阅读文本")
                    self.navigationController?.pushViewController(fullTextVC, animated: true)
                } else {
                    // User tasks: present edit modally (same as normal tap behavior)
                    let inputVC = TextInputViewController(initialText: text)
                    inputVC.onSave = { [weak self] newText in
                        guard let self = self, let task = self.task else { return }
                        task.expectedTexts[indexPath.row] = newText
                        TaskManager.shared.updateTask(task)
                        self.tableView.reloadData()
                    }
                    let nav = UINavigationController(rootViewController: inputVC)
                    self.present(nav, animated: true)
                }
            }

            return previewVC

        case 2:
            // Preview: historical reading session
            let session = task.sessions[indexPath.row]
            let expectedText = session.expectedTextIndex < task.expectedTexts.count
                ? task.expectedTexts[session.expectedTextIndex]
                : nil
            let content = PreviewViewController.PreviewContent.sessionResult(
                session: session,
                expectedText: expectedText
            )
            let previewVC = PreviewViewController(content: content)

            // Set commit action: push to result view if available
            previewVC.onCommit = { [weak self] in
                guard let self = self, let task = self.task,
                      indexPath.row < task.sessions.count else { return }
                let session = task.sessions[indexPath.row]
                if let result = session.result {
                    let resultVC = ResultViewController(result: result)
                    self.navigationController?.pushViewController(resultVC, animated: true)
                }
            }

            return previewVC

        default:
            return nil
        }
    }

    /// Called when the user presses deeper (pop).
    /// Executes the commit action to navigate to the full view.
    func previewingContext(_ previewingContext: UIViewControllerPreviewing,
                           commit viewControllerToCommit: UIViewController) {
        guard let previewVC = viewControllerToCommit as? PreviewViewController else { return }
        previewVC.onCommit?()
    }
}

// MARK: - Full Text Preview View Controller (for built-in task text viewing)
/// A simple view controller to display full text content.
/// Used when 3D Touch commits on a built-in task's expected text.
final class TextPreviewFullViewController: UIViewController {

    private let displayText: String
    private let navTitle: String

    init(text: String, title: String) {
        self.displayText = text
        self.navTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        self.title = navTitle

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let label = UILabel()
        label.text = displayText
        label.font = UIFont.systemFont(ofSize: 16)
        label.textColor = .textPrimary
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(label)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: compatSafeAreaTop, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            label.topAnchor.constraint(equalTo: scrollView.topAnchor),
            label.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            label.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
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

        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "保存", style: .plain, target: self, action: #selector(saveTapped))

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

// MARK: - AVAudioPlayerDelegate
extension TaskDetailViewController: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stopPlayback()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            print("[TaskDetailVC] Audio decode error: \(error.localizedDescription)")
        }
        stopPlayback()
    }
}
