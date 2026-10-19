import AppKit
import Combine
import Foundation

/// One user-visible app that a profile can be bound to.
struct BindableApp: Identifiable, Equatable {
    let bundleID: String
    let name: String

    var id: String { bundleID }
}

/// Switches the keyboard profile when a bound app becomes frontmost.
///
/// Bindings are chosen from the running applications instead of "whatever is
/// frontmost": the configuration app is always frontmost while the user works
/// here, so binding the frontmost app would only ever bind MCHOSE Mac itself,
/// which is deliberately excluded from auto-switching.
@MainActor
final class ProfileSwitcher: ObservableObject {
    static let shared = ProfileSwitcher()

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled {
                cancelPendingSwitch()
            }
        }
    }

    @Published var mappings: [String: Int] {
        didSet {
            UserDefaults.standard.set(mappings, forKey: Self.mappingsKey)
        }
    }

    @Published private(set) var bindableApps: [BindableApp] = []

    var onSwitch: ((Int) -> Void)?

    private static let enabledKey = "mchose.autoSwitchEnabled"
    private static let mappingsKey = "mchose.profileMappings"

    /// Debounce window for app activation changes. Rapid Cmd+Tab sequences
    /// collapse into a single profile switch, matching the design spec.
    private static let switchDebounce: TimeInterval = 0.35

    private var observers: [NSObjectProtocol] = []
    private var lastBundleID: String?
    private var pendingWorkItem: DispatchWorkItem?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)

        let raw = UserDefaults.standard.dictionary(forKey: Self.mappingsKey) ?? [:]
        mappings = raw.compactMapValues { value in
            if let number = value as? NSNumber { return number.intValue }
            return value as? Int
        }
        // Bindings to this app can only come from the old "bind frontmost app"
        // flow; they can never fire, so drop them.
        mappings.removeValue(forKey: Bundle.main.bundleIdentifier ?? "")

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFrontmost(trigger: true)
            }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshBindableApps()
                }
            })
        }

        updateFrontmost()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    func start() {
        updateFrontmost()
    }

    /// Binds one of the running apps to a profile.
    func bind(_ app: BindableApp, to profile: Int) {
        mappings[app.bundleID] = profile
    }

    func remove(_ bundleID: String) {
        mappings.removeValue(forKey: bundleID)
    }

    /// Best-effort display name for a bound bundle id.
    func name(for bundleID: String) -> String {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            return running.localizedName ?? bundleID
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    private func refreshBindableApps() {
        let ownID = Bundle.main.bundleIdentifier
        bindableApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let bundleID = app.bundleIdentifier, bundleID != ownID else { return nil }
                return BindableApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func updateFrontmost(trigger: Bool = false) {
        refreshBindableApps()

        let app = NSWorkspace.shared.frontmostApplication
        let bundleID = app?.bundleIdentifier

        guard trigger,
              isEnabled,
              let bundleID,
              bundleID != Bundle.main.bundleIdentifier,
              bundleID != lastBundleID else {
            lastBundleID = bundleID
            return
        }

        lastBundleID = bundleID
        guard let profile = mappings[bundleID] else { return }

        pendingWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onSwitch?(profile)
        }
        pendingWorkItem = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.switchDebounce,
            execute: item
        )
    }

    private func cancelPendingSwitch() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }
}
