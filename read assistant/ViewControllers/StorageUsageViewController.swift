import UIKit

// MARK: - Storage Usage View Controller
/// Displays storage usage statistics and detailed breakdown by category.
final class StorageUsageViewController: UIViewController {
    
    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let storageManager = StorageManager.shared
    
    private var categories: [StorageCategory] = []
    private var totalSize: Int64 = 0
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        refreshData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshData()
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        title = "储存空间占用"
        view.backgroundColor = .background
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        tableView.register(StorageSummaryCell.self, forCellReuseIdentifier: "SummaryCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Clear cache button in navigation bar
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "清除缓存",
            style: .plain,
            target: self,
            action: #selector(clearCacheTapped)
        )
    }
    
    // MARK: - Data
    private func refreshData() {
        categories = storageManager.calculateStorage()
        totalSize = categories.reduce(0) { $0 + $1.totalSize }
        tableView.reloadData()
    }
    
    // MARK: - Actions
    @objc private func clearCacheTapped() {
        let alert = UIAlertController(
            title: "清除缓存",
            message: "确定要清除所有缓存和临时文件吗？这不会影响您的任务数据和录音文件。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            self?.storageManager.clearCache { success, message in
                DispatchQueue.main.async {
                    self?.refreshData()
                    self?.showAlert(title: success ? "完成" : "错误", message: message)
                }
            }
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension StorageUsageViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        // Summary section + one section per category
        return 1 + categories.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1 // Summary cell
        }
        let categoryIndex = section - 1
        guard categoryIndex < categories.count else { return 0 }
        return categories[categoryIndex].items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            // Summary cell
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "SummaryCell", for: indexPath) as? StorageSummaryCell else {
                return UITableViewCell()
            }
            cell.configure(totalSize: totalSize, categories: categories)
            return cell
        }
        
        // Item cell — use subtitle style for name + detail
        let categoryIndex = indexPath.section - 1
        let category = categories[categoryIndex]
        let item = category.items[indexPath.row]
        
        let cell: UITableViewCell
        if let reused = tableView.dequeueReusableCell(withIdentifier: "StorageCell") {
            cell = reused
        } else {
            cell = UITableViewCell(style: .subtitle, reuseIdentifier: "StorageCell")
        }
        cell.textLabel?.text = item.name
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15)
        cell.textLabel?.textColor = .textPrimary
        cell.detailTextLabel?.text = item.detail
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 12)
        cell.detailTextLabel?.textColor = .textSecondary
        
        // Show size as a right-aligned label
        let sizeLabel = UILabel()
        sizeLabel.text = StorageManager.formatBytes(item.sizeInBytes)
        sizeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        sizeLabel.textColor = .textSecondary
        sizeLabel.sizeToFit()
        cell.accessoryView = sizeLabel
        cell.selectionStyle = .none
        cell.backgroundColor = .cardBackground
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "总览"
        }
        let categoryIndex = section - 1
        guard categoryIndex < categories.count else { return nil }
        let category = categories[categoryIndex]
        return "\(category.icon)  \(category.title)（\(StorageManager.formatBytes(category.totalSize))）"
    }
}

// MARK: - UITableViewDelegate
extension StorageUsageViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 {
            // Title + size + progress bar + legend items
            let legendRows = max(categories.count, 1)
            return CGFloat(100 + 24 + 8 + legendRows * 24)
        }
        return 55
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Storage Summary Cell
/// A custom cell that displays the total storage usage with a colored progress bar and legend.
final class StorageSummaryCell: UITableViewCell {
    
    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let sizeLabel = UILabel()
    private let progressBar = UIView()
    private let legendStack = UIStackView()
    
    private var segmentConstraints: [NSLayoutConstraint] = []
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupSubviews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupSubviews() {
        selectionStyle = .none
        backgroundColor = .clear
        
        containerView.backgroundColor = .cardBackground
        containerView.layer.cornerRadius = 12
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowOpacity = 0.05
        containerView.layer.shadowRadius = 4
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)
        
        titleLabel.text = "总占用空间"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        titleLabel.textColor = .textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)
        
        sizeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 32, weight: .bold)
        sizeLabel.textColor = .primary
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(sizeLabel)
        
        progressBar.backgroundColor = .separator
        progressBar.layer.cornerRadius = 3
        progressBar.clipsToBounds = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(progressBar)
        
        legendStack.axis = .vertical
        legendStack.spacing = 2
        legendStack.alignment = .fill
        legendStack.distribution = .fillEqually
        legendStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(legendStack)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            sizeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            sizeLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            sizeLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            
            progressBar.topAnchor.constraint(equalTo: sizeLabel.bottomAnchor, constant: 12),
            progressBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            progressBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            progressBar.heightAnchor.constraint(equalToConstant: 6),
            
            legendStack.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 8),
            legendStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            legendStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            legendStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12)
        ])
    }
    
    func configure(totalSize: Int64, categories: [StorageCategory]) {
        sizeLabel.text = totalSize > 0 ? StorageManager.formatBytes(totalSize) : "0 KB"
        
        // Remove old segments
        progressBar.subviews.forEach { $0.removeFromSuperview() }
        NSLayoutConstraint.deactivate(segmentConstraints)
        segmentConstraints.removeAll()
        
        // Remove old legend entries
        legendStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        guard totalSize > 0, !categories.isEmpty else {
            // Empty state — show a thin gray fill
            let emptyFill = UIView()
            emptyFill.backgroundColor = .separator
            emptyFill.translatesAutoresizingMaskIntoConstraints = false
            progressBar.addSubview(emptyFill)
            segmentConstraints = [
                emptyFill.topAnchor.constraint(equalTo: progressBar.topAnchor),
                emptyFill.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor),
                emptyFill.trailingAnchor.constraint(equalTo: progressBar.trailingAnchor),
                emptyFill.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor)
            ]
            NSLayoutConstraint.activate(segmentConstraints)
            return
        }
        
        // Build colored segments
        var previousSegment: UIView?
        for category in categories {
            let fraction = CGFloat(category.totalSize) / CGFloat(totalSize)
            
            let segment = UIView()
            segment.backgroundColor = category.barColor
            segment.translatesAutoresizingMaskIntoConstraints = false
            progressBar.addSubview(segment)
            
            var constraints: [NSLayoutConstraint] = [
                segment.topAnchor.constraint(equalTo: progressBar.topAnchor),
                segment.bottomAnchor.constraint(equalTo: progressBar.bottomAnchor),
                segment.widthAnchor.constraint(equalTo: progressBar.widthAnchor, multiplier: fraction)
            ]
            
            if let prev = previousSegment {
                constraints.append(segment.leadingAnchor.constraint(equalTo: prev.trailingAnchor))
            } else {
                constraints.append(segment.leadingAnchor.constraint(equalTo: progressBar.leadingAnchor))
            }
            
            NSLayoutConstraint.activate(constraints)
            segmentConstraints.append(contentsOf: constraints)
            previousSegment = segment
            
            // Add legend entry
            let percent = totalSize > 0 ? Int(round(Double(category.totalSize) / Double(totalSize) * 100)) : 0
            let legendRow = makeLegendRow(icon: category.icon, title: category.title, color: category.barColor, size: category.totalSize, percent: percent)
            legendStack.addArrangedSubview(legendRow)
        }
    }
    
    private func makeLegendRow(icon: String, title: String, color: UIColor, size: Int64, percent: Int) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        
        let dot = UIView()
        dot.backgroundColor = color
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(dot)
        
        let label = UILabel()
        label.text = "\(icon)  \(title)  \(StorageManager.formatBytes(size))（\(percent)%）"
        label.font = UIFont.systemFont(ofSize: 12)
        label.textColor = .textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)
        
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor)
        ])
        
        return row
    }
}
