import UIKit

// MARK: - iOS 10 Compatible Safe Area Helpers
/// Provides safe area anchors compatible with iOS 10.
/// On iOS 10, uses topLayoutGuide/bottomLayoutGuide.
/// On iOS 11+, uses safeAreaLayoutGuide.
extension UIViewController {

    /// Top anchor compatible with iOS 10+.
    var compatSafeAreaTop: NSLayoutYAxisAnchor {
        if #available(iOS 11.0, *) {
            return view.safeAreaLayoutGuide.topAnchor
        } else {
            return topLayoutGuide.bottomAnchor
        }
    }

    /// Bottom anchor compatible with iOS 10+.
    var compatSafeAreaBottom: NSLayoutYAxisAnchor {
        if #available(iOS 11.0, *) {
            return view.safeAreaLayoutGuide.bottomAnchor
        } else {
            return bottomLayoutGuide.topAnchor
        }
    }

    /// Leading anchor compatible with iOS 10+.
    var compatSafeAreaLeading: NSLayoutXAxisAnchor {
        if #available(iOS 11.0, *) {
            return view.safeAreaLayoutGuide.leadingAnchor
        } else {
            return view.leadingAnchor
        }
    }

    /// Trailing anchor compatible with iOS 10+.
    var compatSafeAreaTrailing: NSLayoutXAxisAnchor {
        if #available(iOS 11.0, *) {
            return view.safeAreaLayoutGuide.trailingAnchor
        } else {
            return view.trailingAnchor
        }
    }
}
