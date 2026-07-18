import Foundation

// MARK: - Reward Manager
/// Central manager for all reward-related state: XP/Level, Coins, Check-in, Inventory.
/// Persists to UserDefaults for iOS 10 compatibility.
final class RewardManager {

    // MARK: - Singleton
    static let shared = RewardManager()

    // MARK: - UserDefaults Keys
    private enum Key {
        static let totalXP = "reward_total_xp"
        static let coins = "reward_coins"
        static let inventory = "reward_inventory"
        static let checkInRecords = "reward_checkin_records"
        static let lastCheckInStreak = "reward_last_checkin_streak"
    }

    // MARK: - Properties
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Initialization
    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - XP & Level

    /// Total accumulated XP.
    var totalXP: Int {
        get { defaults.integer(forKey: Key.totalXP) }
        set { defaults.set(newValue, forKey: Key.totalXP) }
    }

    /// Current level based on total XP (range 1-99).
    var currentLevel: Int {
        var level = 1
        while level < 99 && LevelTitle.xpForLevel(level + 1) <= totalXP {
            level += 1
        }
        return min(level, 99)
    }

    /// XP progress within the current level (value between 0 and 1).
    var levelProgress: Double {
        let currentLevelXP = LevelTitle.xpForLevel(currentLevel)
        let nextLevelXP = currentLevel >= 99
            ? LevelTitle.xpForLevel(99)
            : LevelTitle.xpForLevel(currentLevel + 1)
        let xpInCurrentLevel = totalXP - currentLevelXP
        let xpNeeded = nextLevelXP - currentLevelXP
        guard xpNeeded > 0 else { return 1.0 }
        return min(Double(xpInCurrentLevel) / Double(xpNeeded), 1.0)
    }

    /// Current level title.
    var currentTitle: LevelTitle {
        return LevelTitle.title(for: currentLevel)
    }

    /// Awards XP based on reading score.
    /// - Parameter score: The reading score (0-100).
    /// - Returns: The amount of XP awarded and whether a level-up occurred.
    @discardableResult
    func awardXP(forScore score: Double) -> (xpGained: Int, leveledUp: Bool, newLevel: Int) {
        let oldLevel = currentLevel
        // XP formula: score * 0.8, minimum 10 XP per session
        let xpGained = max(Int(score * 0.8), 10)
        totalXP += xpGained

        let newLevel = currentLevel
        let leveledUp = newLevel > oldLevel
        return (xpGained, leveledUp, newLevel)
    }

    // MARK: - Coins

    /// Total coins the user has.
    var coins: Int {
        get { defaults.integer(forKey: Key.coins) }
        set { defaults.set(newValue, forKey: Key.coins) }
    }

    /// Awards coins based on reading score. Only awards coins when score >= 80.
    /// - Parameter score: The reading score (0-100).
    /// - Returns: The amount of coins awarded, or 0 if score < 80.
    @discardableResult
    func awardCoins(forScore score: Double) -> Int {
        guard score >= 80 else { return 0 }
        // Base 10 coins + (score - 80) * 0.5 extra
        let coinsGained = max(Int(10 + (score - 80) * 0.5), 10)
        coins += coinsGained
        return coinsGained
    }

    /// Spends coins to purchase a shop item.
    /// - Returns: true if successful, false if insufficient coins.
    func spendCoins(_ amount: Int) -> Bool {
        guard coins >= amount else { return false }
        coins -= amount
        return true
    }

    // MARK: - Inventory

    /// All inventory items (not yet redeemed).
    var inventoryItems: [InventoryItem] {
        get {
            guard let data = defaults.data(forKey: Key.inventory) else { return [] }
            do {
                return try decoder.decode([InventoryItem].self, from: data)
            } catch {
                print("[RewardManager] Failed to decode inventory: \(error)")
                return []
            }
        }
        set {
            do {
                let data = try encoder.encode(newValue)
                defaults.set(data, forKey: Key.inventory)
            } catch {
                print("[RewardManager] Failed to encode inventory: \(error)")
            }
        }
    }

    /// Adds an item to the inventory.
    func addInventoryItem(shopItem: ShopItem, source: InventoryItem.AcquisitionSource) {
        let item = InventoryItem(
            id: UUID().uuidString,
            shopItemId: shopItem.id,
            name: shopItem.name,
            icon: shopItem.icon,
            acquiredDate: Date(),
            source: source,
            isRedeemed: false,
            redeemedDate: nil
        )
        var items = inventoryItems
        items.append(item)
        inventoryItems = items
    }

    /// Redeems (consumes) an inventory item, removing it.
    func redeemInventoryItem(withId itemId: String) -> Bool {
        var items = inventoryItems
        guard let index = items.firstIndex(where: { $0.id == itemId }) else { return false }
        items.remove(at: index)
        inventoryItems = items
        return true
    }

    // MARK: - Check-in

    /// All check-in records.
    var checkInRecords: [CheckInRecord] {
        get {
            guard let data = defaults.data(forKey: Key.checkInRecords) else { return [] }
            do {
                return try decoder.decode([CheckInRecord].self, from: data)
            } catch {
                print("[RewardManager] Failed to decode check-in records: \(error)")
                return []
            }
        }
        set {
            // Keep only last 60 days of records
            let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let filtered = newValue.filter { record in
                if let date = dateFormatter.date(from: record.date) {
                    return date >= cutoff
                }
                return false
            }
            do {
                let data = try encoder.encode(filtered)
                defaults.set(data, forKey: Key.checkInRecords)
            } catch {
                print("[RewardManager] Failed to encode check-in records: \(error)")
            }
        }
    }

    /// Records a check-in for today (called when a reading session is completed).
    /// - Returns: Any check-in reward earned today.
    @discardableResult
    func recordCheckIn() -> CheckInRewardResult {
        let today = dateString(from: Date())
        var records = checkInRecords

        // If today already recorded, just update
        if let index = records.firstIndex(where: { $0.date == today }) {
            records[index] = CheckInRecord(date: today, hasReading: true, rewardClaimed: records[index].rewardClaimed)
            checkInRecords = records
            return .none
        }

        // New check-in for today
        records.append(CheckInRecord(date: today, hasReading: true, rewardClaimed: nil))
        checkInRecords = records

        // Check consecutive streak
        let streak = calculateConsecutiveStreak(from: records)
        var result: CheckInRewardResult = .none

        if streak >= 7 && !hasClaimedReward(.day7, in: records) {
            // 7-day reward
            if let item = ShopCatalog.item(withId: "amusement_park") {
                addInventoryItem(shopItem: item, source: .checkIn7)
            }
            markRewardClaimed(.day7, for: today, in: &records)
            checkInRecords = records
            result = .day7(itemName: "周末去游乐园")
        } else if streak >= 3 && !hasClaimedReward(.day3, in: records) {
            // 3-day reward
            if let item = ShopCatalog.item(withId: "cartoon") {
                addInventoryItem(shopItem: item, source: .checkIn3)
            }
            markRewardClaimed(.day3, for: today, in: &records)
            checkInRecords = records
            result = .day3(itemName: "看一集动画片")
        }

        return result
    }

    /// Returns this week's check-in status (Sun-Sat).
    func weeklyCheckInStatus() -> [(date: Date, dayName: String, hasReading: Bool)] {
        let calendar = Calendar.current
        let today = Date()
        // Find the start of the current week (Sunday)
        var startOfWeek = today
        while calendar.component(.weekday, from: startOfWeek) != 1 {
            startOfWeek = calendar.date(byAdding: .day, value: -1, to: startOfWeek) ?? startOfWeek
        }

        let records = checkInRecords
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let dayNames = ["日", "一", "二", "三", "四", "五", "六"]

        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startOfWeek) ?? startOfWeek
            let dateStr = dateFormatter.string(from: date)
            let hasReading = records.contains { $0.date == dateStr && $0.hasReading }
            let weekday = calendar.component(.weekday, from: date) - 1 // Sun=0
            return (date, dayNames[weekday], hasReading)
        }
    }

    /// Current consecutive check-in streak.
    func currentStreak() -> Int {
        return calculateConsecutiveStreak(from: checkInRecords)
    }

    // MARK: - Private Helpers

    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func calculateConsecutiveStreak(from records: [CheckInRecord]) -> Int {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let readingDates = records
            .filter { $0.hasReading }
            .compactMap { dateFormatter.date(from: $0.date) }
            .map { calendar.startOfDay(for: $0) }
            .sorted(by: >) // most recent first

        guard !readingDates.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
        // Check if the most recent reading is today or yesterday
        guard let mostRecent = readingDates.first else { return 0 }
        let daysSinceLastReading = calendar.dateComponents([.day], from: mostRecent, to: today).day ?? 0
        if daysSinceLastReading > 1 { return 0 }

        var streak = 1
        var currentDate = mostRecent
        for i in 1..<readingDates.count {
            let prevDate = readingDates[i]
            let daysDiff = calendar.dateComponents([.day], from: prevDate, to: currentDate).day ?? 0
            if daysDiff == 1 {
                streak += 1
                currentDate = prevDate
            } else {
                break
            }
        }
        return streak
    }

    private func hasClaimedReward(_ type: CheckInRecord.CheckInRewardType, in records: [CheckInRecord]) -> Bool {
        return records.contains { $0.rewardClaimed == type }
    }

    private func markRewardClaimed(_ type: CheckInRecord.CheckInRewardType, for dateStr: String, in records: inout [CheckInRecord]) {
        if let index = records.firstIndex(where: { $0.date == dateStr }) {
            records[index] = CheckInRecord(
                date: records[index].date,
                hasReading: records[index].hasReading,
                rewardClaimed: type
            )
        }
    }

    // MARK: - Check-in Reward Result

    enum CheckInRewardResult {
        case none
        case day3(itemName: String)
        case day7(itemName: String)

        var isRewarded: Bool {
            if case .none = self { return false }
            return true
        }
    }
}
