import AppKit

/// Checks GitHub Releases for a newer version. It doesn't install anything by itself:
/// it tells the user and offers to download the new .dmg.
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release {
        let version: String
        let download: URL
    }

    enum Outcome {
        case newer(Release)
        case upToDate
        case failed
    }

    private enum Key {
        static let automatic = "checkForUpdates"
        static let lastCheck = "lastUpdateCheck"
        static let notifiedVersion = "notifiedUpdateVersion"
    }

    private static let interval: TimeInterval = 24 * 3600

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var failed = false
    @Published private(set) var lastCheck: Date?
    @Published var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: Key.automatic)
            if automaticChecks { checkIfDue() }
        }
    }

    /// Called on the main thread when an automatic check finds a version the user hasn't been told about yet.
    var onNewVersion: ((Release) -> Void)?

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private init() {
        defaults.register(defaults: [Key.automatic: true])
        automaticChecks = defaults.bool(forKey: Key.automatic)
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
    }

    /// Starts the automatic checks: shortly after launch and then once a day.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
    }

    private func checkIfDue() {
        guard automaticChecks, !checking else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < Updater.interval { return }
        check { [weak self] outcome in
            guard let self, case .newer(let release) = outcome else { return }
            // Tell the user once per version; they can always find it again in the menu or the About tab.
            if self.defaults.string(forKey: Key.notifiedVersion) != release.version {
                self.defaults.set(release.version, forKey: Key.notifiedVersion)
                self.onNewVersion?(release)
            }
        }
    }

    /// Asks GitHub for the latest release. The completion runs on the main thread.
    func check(completion: ((Outcome) -> Void)? = nil) {
        guard !checking else { return }
        checking = true
        var request = URLRequest(url: Project.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CentralClic/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                guard let self else { return }
                let outcome = self.outcome(data: data, status: status, error: error)
                self.checking = false
                switch outcome {
                case .newer(let release):
                    self.available = release
                    self.failed = false
                case .upToDate:
                    self.available = nil
                    self.failed = false
                case .failed:
                    self.failed = true
                }
                if case .failed = outcome {} else {
                    self.lastCheck = Date()
                    self.defaults.set(self.lastCheck, forKey: Key.lastCheck)
                }
                appLog.notice("Update check: \(String(describing: outcome), privacy: .public)")
                completion?(outcome)
            }
        }.resume()
    }

    func openDownload() {
        if let available { NSWorkspace.shared.open(available.download) }
    }

    private func outcome(data: Data?, status: Int, error: Error?) -> Outcome {
        if error != nil { return .failed }
        if status == 404 { return .upToDate } // the repository has no releases yet
        guard status == 200, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return .failed }

        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        guard Updater.isVersion(version, newerThan: currentVersion) else { return .upToDate }

        // Prefer the .dmg attached to the release; otherwise the release page.
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets
            .first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
        return .newer(Release(version: version, download: dmg ?? page))
    }

    /// Compares dotted versions numerically ("1.10.0" > "1.9.2").
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
