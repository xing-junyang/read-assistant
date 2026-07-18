import UIKit

// MARK: - Settings View Controller
/// Settings page with About and Developer Settings entries.
final class SettingsViewController: UIViewController {

    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .grouped)

    private enum Section: Int, CaseIterable {
        case general
        case developer

        var title: String {
            switch self {
            case .general: return "通用"
            case .developer: return "开发者"
            }
        }
    }

    private struct Item {
        let title: String
        let icon: String
        let accessoryType: UITableViewCell.AccessoryType
        let action: () -> Void
    }

    private var dataSource: [[Item]] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        buildDataSource()
        tableView.reloadData()
    }

    // MARK: - UI Setup
    private func setupUI() {
        title = "设置"
        view.backgroundColor = .background

        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SettingsCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildDataSource() {
        dataSource = [
            // General
            [
                Item(title: "关于", icon: "ℹ️", accessoryType: .disclosureIndicator) { [weak self] in
                    self?.navigateToAbout()
                }
            ],
            // Developer
            [
                Item(title: "开发者设置", icon: "🔧", accessoryType: .disclosureIndicator) { [weak self] in
                    self?.navigateToDeveloperSettings()
                }
            ]
        ]
    }

    // MARK: - Navigation
    private func navigateToAbout() {
        let aboutVC = AboutViewController()
        navigationController?.pushViewController(aboutVC, animated: true)
    }

    private func navigateToDeveloperSettings() {
        // Show password prompt first
        let alert = UIAlertController(
            title: "开发者设置",
            message: "请输入开发者密码",
            preferredStyle: .alert
        )
        alert.addTextField { textField in
            textField.placeholder = "密码"
            textField.isSecureTextEntry = true
            textField.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认", style: .default) { [weak self] _ in
            guard let password = alert.textFields?.first?.text else { return }
            if DeveloperPasswordManager.shared.verify(password: password) {
                let devVC = DeveloperSettingsViewController()
                self?.navigationController?.pushViewController(devVC, animated: true)
            } else {
                self?.showAlert(title: "错误", message: "密码错误，无法访问开发者设置")
            }
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension SettingsViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return dataSource.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SettingsCell", for: indexPath)
        let item = dataSource[indexPath.section][indexPath.row]
        cell.textLabel?.text = "\(item.icon)  \(item.title)"
        cell.textLabel?.font = UIFont.systemFont(ofSize: 16)
        cell.textLabel?.textColor = .textPrimary
        cell.accessoryType = item.accessoryType
        cell.backgroundColor = .cardBackground
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return Section(rawValue: section)?.title
    }
}

// MARK: - UITableViewDelegate
extension SettingsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        dataSource[indexPath.section][indexPath.row].action()
    }
}

// MARK: - Developer Password Manager
/// Manages password verification for developer settings.
/// Uses SHA-256 with a random salt to store the password hash securely.
final class DeveloperPasswordManager {

    static let shared = DeveloperPasswordManager()

    /// Salt used for password hashing (hex-encoded).
    private let saltHex = "a3f7b2c91e4d5608"

    /// SHA-256 hash of (salt + "20040513"), hex-encoded.
    private let passwordHashHex = "7df26f5b8b6e839ed8631d8f286be6fd35a104003dbad93f2240b9f9f01e056d"

    private init() {}

    /// Verifies if the input password matches the stored password.
    /// - Parameter password: The password string to verify.
    /// - Returns: `true` if the password is correct.
    func verify(password: String) -> Bool {
        let expectedHash = hash(password: password)
        // Use constant-time comparison to prevent timing attacks
        return constantTimeCompare(expectedHash, passwordHashHex)
    }

    /// Computes SHA-256 hash of (salt + password).
    private func hash(password: String) -> String {
        let combined = saltHex + password
        return SHA256.hash(combined)
    }

    /// Constant-time string comparison to prevent timing attacks.
    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        var result: UInt8 = 0
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }
}

// MARK: - Pure Swift SHA-256 Implementation
/// Self-contained SHA-256 implementation that works on iOS 10+ without CommonCrypto.
private struct SHA256 {

    /// Computes SHA-256 hash of a string, returns lowercase hex.
    static func hash(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "" }
        let digest = hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Computes SHA-256 hash of Data.
    static func hash(data: Data) -> [UInt8] {
        // SHA-256 initial hash values
        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]
        var message = data

        // Pre-processing: padding
        let msgLen = message.count
        let bitLen = UInt64(msgLen) * 8

        // Append 0x80
        message.append(0x80)

        // Pad with zeros until (length + 8) % 64 == 0
        while (message.count + 8) % 64 != 0 {
            message.append(0x00)
        }

        // Append bit length as big-endian 64-bit
        var bigEndianLen = bitLen.bigEndian
        withUnsafeBytes(of: &bigEndianLen) { message.append(contentsOf: $0) }

        // Process 64-byte blocks
        let blockCount = message.count / 64
        for i in 0..<blockCount {
            let blockStart = i * 64
            var w = [UInt32](repeating: 0, count: 64)

            // Prepare message schedule
            for t in 0..<16 {
                let offset = blockStart + t * 4
                w[t] = (UInt32(message[offset]) << 24) |
                       (UInt32(message[offset + 1]) << 16) |
                       (UInt32(message[offset + 2]) << 8) |
                       UInt32(message[offset + 3])
            }
            for t in 16..<64 {
                let s0 = rightRotate(w[t - 15], by: 7) ^ rightRotate(w[t - 15], by: 18) ^ (w[t - 15] >> 3)
                let s1 = rightRotate(w[t - 2], by: 17) ^ rightRotate(w[t - 2], by: 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }

            // Initialize working variables
            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]

            // Compression
            for t in 0..<64 {
                let S1 = rightRotate(e, by: 6) ^ rightRotate(e, by: 11) ^ rightRotate(e, by: 25)
                let ch = (e & f) ^ (~e & g)
                let temp1 = h &+ S1 &+ ch &+ K[t] &+ w[t]
                let S0 = rightRotate(a, by: 2) ^ rightRotate(a, by: 13) ^ rightRotate(a, by: 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = S0 &+ maj

                h = g; g = f; f = e; e = d &+ temp1
                d = c; c = b; b = a; a = temp1 &+ temp2
            }

            hash[0] = hash[0] &+ a; hash[1] = hash[1] &+ b; hash[2] = hash[2] &+ c; hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e; hash[5] = hash[5] &+ f; hash[6] = hash[6] &+ g; hash[7] = hash[7] &+ h
        }

        // Convert to bytes
        var result = [UInt8]()
        for value in hash {
            result.append(UInt8((value >> 24) & 0xFF))
            result.append(UInt8((value >> 16) & 0xFF))
            result.append(UInt8((value >> 8) & 0xFF))
            result.append(UInt8(value & 0xFF))
        }
        return result
    }

    private static func rightRotate(_ value: UInt32, by amount: UInt32) -> UInt32 {
        return (value >> amount) | (value << (32 - amount))
    }

    /// SHA-256 round constants
    private static let K: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]
}
