import Foundation

// MARK: - Reward Models
/// All reward-related data models for the reading assistant app.
/// Uses UserDefaults for iOS 10 compatible persistence.

// MARK: - XP & Level System

/// Represents a title earned at certain level milestones.
struct LevelTitle {
    let minLevel: Int
    let maxLevel: Int
    let title: String
    let icon: String

    static let allTitles: [LevelTitle] = [
        LevelTitle(minLevel: 1, maxLevel: 9, title: "阅读新手", icon: "🌱"),
        LevelTitle(minLevel: 10, maxLevel: 19, title: "阅读学徒", icon: "📚"),
        LevelTitle(minLevel: 20, maxLevel: 29, title: "阅读达人", icon: "⭐"),
        LevelTitle(minLevel: 30, maxLevel: 39, title: "阅读高手", icon: "🌟"),
        LevelTitle(minLevel: 40, maxLevel: 49, title: "阅读专家", icon: "💎"),
        LevelTitle(minLevel: 50, maxLevel: 59, title: "阅读大师", icon: "👑"),
        LevelTitle(minLevel: 60, maxLevel: 69, title: "阅读宗师", icon: "🏆"),
        LevelTitle(minLevel: 70, maxLevel: 79, title: "阅读传说", icon: "🐉"),
        LevelTitle(minLevel: 80, maxLevel: 89, title: "阅读神话", icon: "✨"),
        LevelTitle(minLevel: 90, maxLevel: 99, title: "阅读至尊", icon: "🔱")
    ]

    /// Returns the title for a given level.
    static func title(for level: Int) -> LevelTitle {
        return allTitles.first { level >= $0.minLevel && level <= $0.maxLevel }
            ?? allTitles.last!
    }

    /// XP required to reach a given level. Uses a progressive curve.
    /// Level 1 = 0 XP, Level 2 = 100 XP, each subsequent level +20 more XP.
    static func xpForLevel(_ level: Int) -> Int {
        guard level > 1 else { return 0 }
        // XP needed: sum of (80 + level*20) for levels 2 through target
        var total = 0
        for lv in 2...level {
            total += 80 + lv * 20
        }
        return total
    }
}

// MARK: - Shop Item

/// Represents a purchasable reward item in the coin shop.
struct ShopItem: Codable, Equatable {
    let id: String
    let name: String
    let icon: String
    let price: Int // Coins required

    static func == (lhs: ShopItem, rhs: ShopItem) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Defines all available shop items.
struct ShopCatalog {
    static let allItems: [ShopItem] = [
        ShopItem(id: "ice_cream", name: "吃一个冰淇淋", icon: "🍦", price: 100),
        ShopItem(id: "subway_surfers", name: "玩地铁跑酷十分钟", icon: "🏃", price: 30),
        ShopItem(id: "cartoon", name: "看一集动画片", icon: "📺", price: 30),
        ShopItem(id: "park", name: "去公园玩", icon: "🌳", price: 50),
        ShopItem(id: "minecraft", name: "玩我的世界十分钟", icon: "⛏️", price: 120),
        ShopItem(id: "new_book", name: "买一本新书", icon: "📖", price: 10),
        ShopItem(id: "toy", name: "选一个玩具", icon: "🎰", price: 300),
        ShopItem(id: "amusement_park", name: "周末去游乐园", icon: "🎢", price: 2000),
        ShopItem(id: "movie", name: "看一场电影", icon: "🎬", price: 1000),
        ShopItem(id: "pizza", name: "吃一顿披萨", icon: "🍕", price: 1000)
    ]

    static func item(withId id: String) -> ShopItem? {
        return allItems.first { $0.id == id }
    }
}

// MARK: - Inventory Item

/// Represents an item in the user's inventory (purchased or check-in reward).
struct InventoryItem: Codable {
    let id: String
    let shopItemId: String
    let name: String
    let icon: String
    let acquiredDate: Date
    let source: AcquisitionSource
    var isRedeemed: Bool
    var redeemedDate: Date?

    enum AcquisitionSource: String, Codable {
        case shop      // Purchased with coins
        case checkIn3  // 3-day check-in reward
        case checkIn7  // 7-day check-in reward
    }
}

// MARK: - Check-in Record

/// Represents a single day's check-in status.
struct CheckInRecord: Codable {
    let date: String // "yyyy-MM-dd" format
    let hasReading: Bool
    let rewardClaimed: CheckInRewardType?

    enum CheckInRewardType: String, Codable {
        case day3
        case day7
    }
}
