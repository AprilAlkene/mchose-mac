import Foundation
import AppKit
import Combine

@MainActor
final class ProfileSwitcher: ObservableObject {
    static let shared = ProfileSwitcher()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    @Published var mappings: [String: Int] {
        didSet {
            UserDefaults.standard.set(mappings, forKey: Self.mappingsKey)
        }
    }

    @Published private(set) var frontmostBundleID: String?
    @Published private(set) var frontmostName: String?

    var onSwitch: ((Int) -> Void)?

    private static let enabledKey = "mchose.autoSwitchEnabled"
    private static let mappingsKey = "mchose.profileMappings"

    private var observer: NSObjectProtocol?
    private var lastBundleID: String?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)

        let raw = UserDefaults.standard.dictionary(forKey: Self.mappingsKey) ?? [:]
        mappings = raw.compactMapValues { value in
            if let number = value as? NSNumber { return number.intValue }
            return value as? Int
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFrontmost(trigger: true)
            }
        }

        updateFrontmost()
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func start() {
        updateFrontmost()
    }

    func bindCurrentApp(to profile: Int) {
        guard let bundleID = frontmostBundleID else { return }
        mappings[bundleID] = profile
    }

    func remove(_ bundleID: String) {
        mappings.removeValue(forKey: bundleID)
    }

    private func updateFrontmost(trigger: Bool = false) {
        let app = NSWorkspace.shared.frontmostApplication
        frontmostBundleID = app?.bundleIdentifier
        frontmostName = app?.localizedName

        guard trigger,
              isEnabled,
              let bundleID = frontmostBundleID,
              bundleID != Bundle.main.bundleIdentifier,
              bundleID != lastBundleID else {
            lastBundleID = frontmostBundleID
            return
        }

        lastBundleID = bundleID
        if let profile = mappings[bundleID] {
            onSwitch?(profile)
        }
    }
}
