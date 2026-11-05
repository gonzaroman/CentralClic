import AppKit

/// Where the project lives, and the gentle ways to support it.
enum Project {
    /// GitHub repository ("owner/name"). Used for releases (updates), stars and sharing.
    static let repository = "gonzaroman/CentralClic"
    static let url = URL(string: "https://github.com/\(repository)")!
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    static var shareMessage: String {
        L("CentralClic adds middle click to the Magic Mouse, with adjustable zones and speed. Free on GitHub:")
    }

    static func openRepository() { NSWorkspace.shared.open(url) }
}

/// Counts middle clicks and, once the app has proven useful, asks one single time for a star or a share.
enum Engagement {
    static let milestone = 100

    private enum Key {
        static let middleClicks = "middleClickCount"
        static let asked = "askedForSupport"
    }

    /// Called on the main thread when the milestone is reached (only ever once).
    static var onMilestone: (() -> Void)?

    static func recordMiddleClick() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Key.asked) else { return }
        let count = defaults.integer(forKey: Key.middleClicks) + 1
        defaults.set(count, forKey: Key.middleClicks)
        if count >= milestone {
            defaults.set(true, forKey: Key.asked)
            // A moment later, so it doesn't pop up in the middle of the click itself.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onMilestone?() }
        }
    }
}
