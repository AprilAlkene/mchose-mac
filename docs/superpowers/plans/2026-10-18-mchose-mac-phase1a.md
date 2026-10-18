# MCHOSE Mac Phase 1a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native SwiftUI macOS app that scans for the connected MCHOSE keyboard, opens the vendor HID interface, reads `getInfo`, and displays product/build-date information. No settings writes.

**Architecture:** XcodeGen-generated macOS app target with local Swift packages `HIDTransport`, `Protocol`, and `Features`. `DeviceStore` is a `@MainActor` observable object; `DeviceConnection` owns the HID handle and CZ session. Phase 1a is a working vertical slice and the foundation for Phase 1b (magnetic/keymap) and Phase 1c (lighting/profiles).

**Tech Stack:** Xcode 27.1, SwiftUI, XcodeGen, Swift Testing, IOKit, SwiftPM.

**Spec:** `docs/superpowers/specs/2026-10-18-mchose-mac-design.md`

## Global Constraints

- macOS 13+, Apple Silicon.
- Personal use: no App Sandbox, no signing/notarization, no App Store.
- Phase 1a is **read-only**: never send Set/Reset/OTA/boot commands.
- Verified device: VID `0x3837`, PID `0x3026`; config interface `usagePage 1 / usage 0`, reportId 0, 64-byte reports.
- Package tests use **Swift Testing**, not XCTest.
- Commit after every task.
- Xcode license must be accepted before any `xcodebuild` command.

---

## Prerequisite: Unblock Xcode

The app build cannot start until the Xcode license is accepted. Run these manually (they require the user's password):

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
brew install xcodegen
```

Verify:

```bash
xcodebuild -version
xcodegen --version
```

Expected: `Xcode 27.1` and an XcodeGen version.

---

## File Structure

```text
~/mchose-mac/
  Package.swift                     # add Features + FeaturesTests
  Sources/Features/
    DeviceManifest.swift
    ManifestLoader.swift
    DeviceMatcher.swift
    DeviceInfo.swift
    DeviceInfoParser.swift
    DeviceConnection.swift
  Tests/FeaturesTests/
    DeviceManifestTests.swift
    DeviceMatcherTests.swift
    DeviceInfoParserTests.swift
  App/
    Sources/
      MCHOSEMacApp.swift
      DeviceStore.swift
      ContentView.swift
      Views/DeviceListView.swift
      Views/DeviceInfoView.swift
      Views/ConnectionStatusView.swift
      Views/MenuBarContent.swift
  project.yml
  docs/captures/ace68-getinfo-fields.md
```

---

## Task 1: Add the Features package and manifest model

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Features/DeviceManifest.swift`
- Create: `Sources/Features/ManifestLoader.swift`
- Test: `Tests/FeaturesTests/DeviceManifestTests.swift`

**Interfaces:**
- Produces: `DeviceManifest`, `ManifestLoader.load(from:)`

- [ ] **Step 1: Add the Features target**

In `Package.swift`, add `Features` to `products`, add the target and test target:

```swift
.library(name: "Features", targets: ["Features"]),
```

```swift
.target(
    name: "Features",
    dependencies: ["HIDTransport", "Protocol"]
),
.testTarget(
    name: "FeaturesTests",
    dependencies: ["Features", "HIDTransport", "Protocol"],
    swiftSettings: testSwiftSettings,
    linkerSettings: testLinkerSettings
),
```

- [ ] **Step 2: Write the failing manifest test**

Create `Tests/FeaturesTests/DeviceManifestTests.swift`:

```swift
import Foundation
import Testing
@testable import Features

@Test func loadsAce68Manifest() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Resources/DeviceManifests/ace68_turbo_16k.json")

    let manifest = try ManifestLoader.load(from: url)

    #expect(manifest.displayName == "Ace 68 Turbo 16K")
    #expect(manifest.protocolFamily == "cz")
    #expect(manifest.verified)
    #expect(manifest.identities.contains {
        $0.vendorId == 0x3837 && $0.productId == 0x3026 && $0.mode == "normal"
    })
    #expect(manifest.configInterface.usagePage == 1)
    #expect(manifest.configInterface.usage == 0)
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
swift test --filter loadsAce68Manifest
```

Expected: FAIL, `DeviceManifest`/`ManifestLoader` are not defined.

- [ ] **Step 4: Implement the manifest model and loader**

Create `Sources/Features/DeviceManifest.swift`:

```swift
public struct DeviceManifest: Codable, Equatable, Sendable {
    public struct Identity: Codable, Equatable, Sendable {
        public let vendorId: Int
        public let productId: Int
        public let mode: String
    }

    public struct ConfigInterface: Codable, Equatable, Sendable {
        public let usagePage: Int
        public let usage: Int
        public let maxReportSize: Int
    }

    public struct Capabilities: Codable, Equatable, Sendable {
        public let magnetic: Bool
        public let keymap: Bool
        public let macros: Bool
        public let socd: Bool
        public let lighting: Bool
        public let perKeyLighting: Bool
        public let gifLighting: Bool
        public let musicSync: Bool
        public let battery: Bool
    }

    public let id: String
    public let displayName: String
    public let protocolFamily: String
    public let identities: [Identity]
    public let configInterface: ConfigInterface
    public let capabilities: Capabilities
    public let profileSlots: Int?
    public let macroSlots: Int?
    public let layoutAsset: String
    public let layoutId: String?
    public let verified: Bool
    public let firmwareVersion: Int?
    public let deviceType: Int?
}
```

Create `Sources/Features/ManifestLoader.swift`:

```swift
import Foundation

public enum ManifestError: Error, LocalizedError {
    case notFound(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let name):
            return "Device manifest \(name).json not found in the app bundle"
        }
    }
}

public enum ManifestLoader {
    public static func load(from url: URL) throws -> DeviceManifest {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DeviceManifest.self, from: data)
    }

    public static func loadBundled(
        named name: String = "ace68_turbo_16k"
    ) throws -> DeviceManifest {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "json"),
            Bundle.main.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "DeviceManifests"
            ),
        ].compactMap { $0 }

        guard let url = candidates.first else {
            throw ManifestError.notFound(name)
        }
        return try load(from: url)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run:

```bash
swift test --filter loadsAce68Manifest
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/Features Tests/FeaturesTests
git commit -m "feat: add device manifest model and loader"
```

---

## Task 2: Match devices to manifests

**Files:**
- Create: `Sources/Features/DeviceMatcher.swift`
- Test: `Tests/FeaturesTests/DeviceMatcherTests.swift`

**Interfaces:**
- Consumes: `DeviceManifest`, `HIDDeviceInfo`
- Produces: `DeviceMatcher.matches(info:manifest:) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `Tests/FeaturesTests/DeviceMatcherTests.swift`:

```swift
import Testing
@testable import Features
@testable import HIDTransport

@Test func matchesVerifiedIdentity() {
    let manifest = DeviceManifest(
        id: "ace68-turbo-16k",
        displayName: "Ace 68 Turbo 16K",
        protocolFamily: "cz",
        identities: [
            .init(vendorId: 0x3837, productId: 0x3026, mode: "normal"),
            .init(vendorId: 0x3837, productId: 0x3027, mode: "boot"),
        ],
        configInterface: .init(usagePage: 1, usage: 0, maxReportSize: 64),
        capabilities: .init(
            magnetic: true, keymap: true, macros: true, socd: true,
            lighting: true, perKeyLighting: true, gifLighting: false,
            musicSync: false, battery: false
        ),
        profileSlots: nil,
        macroSlots: nil,
        layoutAsset: "Layouts/ace68_turbo_16k.json",
        layoutId: nil,
        verified: true,
        firmwareVersion: 122,
        deviceType: 211
    )

    let info = HIDDeviceInfo(
        product: "Ace 68 Turbo 16K",
        identity: HIDDeviceIdentity(vendorId: 0x3837, productId: 0x3026),
        interface: HIDInterfaceDescriptor(
            usagePage: 1, usage: 0,
            maxInputReportSize: 64, maxOutputReportSize: 64
        ),
        transport: "USB",
        registryId: 1
    )

    #expect(DeviceMatcher.matches(info: info, manifest: manifest))
}

@Test func rejectsUnknownIdentity() {
    let manifest = DeviceManifest(
        id: "ace68-turbo-16k",
        displayName: "Ace 68 Turbo 16K",
        protocolFamily: "cz",
        identities: [.init(vendorId: 0x3837, productId: 0x3026, mode: "normal")],
        configInterface: .init(usagePage: 1, usage: 0, maxReportSize: 64),
        capabilities: .init(
            magnetic: true, keymap: true, macros: true, socd: true,
            lighting: true, perKeyLighting: true, gifLighting: false,
            musicSync: false, battery: false
        ),
        profileSlots: nil,
        macroSlots: nil,
        layoutAsset: "",
        layoutId: nil,
        verified: true,
        firmwareVersion: nil,
        deviceType: nil
    )

    let info = HIDDeviceInfo(
        product: "Unknown",
        identity: HIDDeviceIdentity(vendorId: 0x1234, productId: 0x5678),
        interface: HIDInterfaceDescriptor(
            usagePage: 1, usage: 0,
            maxInputReportSize: 64, maxOutputReportSize: 64
        ),
        transport: "USB",
        registryId: 2
    )

    #expect(!DeviceMatcher.matches(info: info, manifest: manifest))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter DeviceMatcherTests
```

Expected: FAIL, `DeviceMatcher` is not defined.

- [ ] **Step 3: Implement the matcher**

Create `Sources/Features/DeviceMatcher.swift`:

```swift
import HIDTransport

public enum DeviceMatcher {
    public static func matches(
        info: HIDDeviceInfo,
        manifest: DeviceManifest
    ) -> Bool {
        manifest.identities.contains { identity in
            identity.mode == "normal"
                && identity.vendorId == info.identity.vendorId
                && identity.productId == info.identity.productId
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
swift test --filter DeviceMatcherTests
```

Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Features/DeviceMatcher.swift Tests/FeaturesTests/DeviceMatcherTests.swift
git commit -m "feat: match HID devices to manifests"
```

---

## Task 3: Map getInfo payload fields

**Files:**
- Create: `docs/captures/ace68-getinfo-fields.md`

**Interfaces:**
- Produces: byte-to-field mapping used by Task 4

- [ ] **Step 1: Open the web SDK in Edge**

```bash
open -a "Microsoft Edge" "https://www.mchose.com.cn/#/connectDevice"
```

Open DevTools Console. Do not connect a real device for this task; use a fake HID device and fabricate the response.

- [ ] **Step 2: Feed varied payloads to the SDK decoder**

In the Console, run this script. It creates an SDK with a fake device, resolves `getInfo` with a fabricated response, and prints the decoded fields:

```javascript
(async () => {
  const key = Object.keys(window).find(
    (k) => k.startsWith("CZ_SHARED_DATA_") && window[k] && window[k].CZ_SHARED_DATA
  );
  const sd = window[key].CZ_SHARED_DATA;
  const entry = Object.values(sd.ALL_DEVICE_DATA).find(
    (d) => d.storageKey === "Ace 68 Turbo 16K"
  );

  async function decode(payloadBytes) {
    const sent = [];
    const fake = {
      productName: "Ace 68 Turbo 16K",
      vendorId: 0x3837,
      productId: 0x3026,
      collections: [{ usagePage: 1, usage: 0, inputReports: [], outputReports: [] }],
      opened: true,
      open: async () => {},
      close: async () => {},
      sendReport: async (id, data) => sent.push({ id, data: Array.from(new Uint8Array(data.buffer || data)) }),
      sendFeatureReport: async () => {},
      receiveFeatureReport: async () => new DataView(new ArrayBuffer(64)),
      addEventListener: () => {},
      removeEventListener: () => {}
    };

    const sdk = await sd.createDeviceSDK(fake, entry);
    const promise = sdk.getInfo();
    await new Promise((r) => setTimeout(r, 30));

    const buf = new Uint8Array(64);
    buf[0] = 0xAA;
    buf[1] = 0x03;
    buf[4] = payloadBytes.length;
    buf.set(payloadBytes, 8);
    sdk.channel.handleMessage({ data: new DataView(buf.buffer) });

    return await Promise.race([
      promise,
      new Promise((resolve) => setTimeout(() => resolve("TIMEOUT"), 500))
    ]);
  }

  const base = [0x26, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, ...Array.from(new TextEncoder().encode("Jul 21 2026,15:16:19"))];
  const results = {};
  results.base = await decode(base);

  for (let i = 0; i < 7; i++) {
    const variant = base.slice();
    variant[i] = 0x00;
    results[`byte${i}=00`] = await decode(variant);
  }

  console.log(JSON.stringify(results, null, 2));
})()
```

- [ ] **Step 3: Record the mapping**

Create `docs/captures/ace68-getinfo-fields.md` with a table:

```markdown
# getInfo payload field mapping

Captured on 2026-10-18 from the web SDK decoder.

| Payload byte | Value in capture | Decoded field | Notes |
|---|---|---|---|
| 0 | 0x26 | ... | ... |
| 1 | 0x01 | ... | ... |
| 2..5 | FF FF FF FF | rffw_ver = ffff | confirm |
| 6 | 0x00 | collabType? | confirm |
| 7..26 | ASCII date | build date | confirmed |
```

Fill every row from the script output. If a field is not identified, write `unidentified`; do not guess.

- [ ] **Step 4: Commit**

```bash
git add docs/captures/ace68-getinfo-fields.md
git commit -m "docs: map getInfo payload fields"
```

---

## Task 4: Parse device info

**Files:**
- Create: `Sources/Features/DeviceInfo.swift`
- Create: `Sources/Features/DeviceInfoParser.swift`
- Test: `Tests/FeaturesTests/DeviceInfoParserTests.swift`

**Interfaces:**
- Consumes: `CZResponse`, Task 3 mapping
- Produces: `DeviceInfo`, `DeviceInfoParser.parse(product:response:) throws -> DeviceInfo`

- [ ] **Step 1: Write the failing test**

Create `Tests/FeaturesTests/DeviceInfoParserTests.swift`:

```swift
import Foundation
import Testing
@testable import Features
@testable import Protocol
@testable import HIDTransport

@Test func parsesBuildDateFromCapturedResponse() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Tests/ProtocolTests/Fixtures/ace68-read-info.json")
    let data = try Data(contentsOf: url)
    let fixture = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let bytes = Hex.parse(fixture["responseHex"] as! String)!
    let response = try CZCodec().decodeResponse(bytes)

    let info = try DeviceInfoParser.parse(
        product: "Ace 68 Turbo 16K",
        response: response
    )

    #expect(info.product == "Ace 68 Turbo 16K")
    #expect(info.buildDate == "Jul 21 2026,15:16:19")
    #expect(info.rawPayload.count == 27)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter parsesBuildDateFromCapturedResponse
```

Expected: FAIL, `DeviceInfo`/`DeviceInfoParser` are not defined.

- [ ] **Step 3: Implement the parser**

Create `Sources/Features/DeviceInfo.swift`:

```swift
public struct DeviceInfo: Equatable, Sendable {
    public let product: String
    public let buildDate: String
    public let firmwareVersion: String?
    public let rffwVersion: String?
    public let collabType: UInt8?
    public let rawPayload: [UInt8]

    public init(
        product: String,
        buildDate: String,
        firmwareVersion: String?,
        rffwVersion: String?,
        collabType: UInt8?,
        rawPayload: [UInt8]
    ) {
        self.product = product
        self.buildDate = buildDate
        self.firmwareVersion = firmwareVersion
        self.rffwVersion = rffwVersion
        self.collabType = collabType
        self.rawPayload = rawPayload
    }
}
```

Create `Sources/Features/DeviceInfoParser.swift`:

```swift
import Foundation
import Protocol

public enum DeviceInfoError: Error, LocalizedError {
    case incompletePayload

    public var errorDescription: String? {
        switch self {
        case .incompletePayload:
            return "getInfo payload is shorter than expected"
        }
    }
}

public enum DeviceInfoParser {
    public static func parse(
        product: String,
        response: CZResponse
    ) throws -> DeviceInfo {
        let payload = response.payload
        guard payload.count >= 20 else {
            throw DeviceInfoError.incompletePayload
        }

        let dateBytes = Array(payload.suffix(20))
        guard let buildDate = String(bytes: dateBytes, encoding: .utf8),
              buildDate.contains(":") else {
            throw DeviceInfoError.incompletePayload
        }

        // Fill these from Task 3's confirmed mapping. Until then they stay nil.
        return DeviceInfo(
            product: product,
            buildDate: buildDate,
            firmwareVersion: nil,
            rffwVersion: nil,
            collabType: nil,
            rawPayload: payload
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:

```bash
swift test --filter parsesBuildDateFromCapturedResponse
```

Expected: PASS.

- [ ] **Step 5: Add the confirmed fields**

Using Task 3's mapping, replace the `nil` fields in `DeviceInfoParser` with the actual decode logic. Add assertions to the test for `firmwareVersion == "126"`, `rffwVersion == "ffff"`, and `collabType == 255` only after the mapping is confirmed by Task 3. If a field remains unidentified, leave it `nil` and keep the UI label as `未识别`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Features/DeviceInfo.swift Sources/Features/DeviceInfoParser.swift Tests/FeaturesTests/DeviceInfoParserTests.swift
git commit -m "feat: parse device info from getInfo response"
```

---

## Task 5: Device connection

**Files:**
- Create: `Sources/Features/DeviceConnection.swift`
- Test: hardware integration only (no unit test for IOKit open)

**Interfaces:**
- Consumes: `HIDDeviceRef`, `HIDDeviceHandle`, `CZSession`, `DeviceInfoParser`
- Produces: `DeviceConnection.connect()`, `.close()`, `.readInfo() throws -> DeviceInfo`

- [ ] **Step 1: Implement the connection**

Create `Sources/Features/DeviceConnection.swift`:

```swift
import Foundation
import HIDTransport
import Protocol

public enum DeviceConnectionError: Error, LocalizedError {
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "The device is not connected"
        }
    }
}

public final class DeviceConnection {
    public let ref: HIDDeviceRef
    public let manifest: DeviceManifest
    private var handle: HIDDeviceHandle?

    public init(ref: HIDDeviceRef, manifest: DeviceManifest) {
        self.ref = ref
        self.manifest = manifest
    }

    public func connect() throws {
        close()
        let handle = HIDDeviceHandle(device: ref.device)
        try handle.open()
        self.handle = handle
    }

    public func close() {
        handle?.close()
        handle = nil
    }

    public func readInfo() throws -> DeviceInfo {
        guard let handle else {
            throw DeviceConnectionError.notConnected
        }
        let session = CZSession(handle: handle)
        let response = try session.getInfo()
        return try DeviceInfoParser.parse(
            product: ref.info.product,
            response: response
        )
    }
}
```

- [ ] **Step 2: Build the package**

Run:

```bash
swift build
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Features/DeviceConnection.swift
git commit -m "feat: add device connection wrapper"
```

---

## Task 6: Generate the Xcode app project

**Files:**
- Create: `project.yml`
- Create: `App/Sources/MCHOSEMacApp.swift`
- Create: `App/Sources/ContentView.swift`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `MCHOSEMac.xcodeproj` (generated), `MCHOSEMac.app`

- [ ] **Step 1: Add the app sources**

Create `App/Sources/MCHOSEMacApp.swift`:

```swift
import SwiftUI

@main
struct MCHOSEMacApp: App {
    @StateObject private var store = DeviceStore()

    var body: some Scene {
        WindowGroup("MCHOSE Mac") {
            ContentView(store: store)
        }

        MenuBarExtra("MCHOSE Mac", systemImage: "keyboard") {
            MenuBarContent(store: store)
        }
    }
}
```

Create `App/Sources/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MCHOSE Mac")
                .font(.largeTitle.bold())

            ConnectionStatusView(store: store)
            DeviceListView(store: store)
            Divider()
            DeviceInfoView(info: store.info)

            Spacer()

            HStack {
                Button("扫描设备") { store.refresh() }
                Button("连接") { store.connectSelected() }
                    .disabled(store.selected == nil)
                Button("断开") { store.disconnectSelected() }
                    .disabled(store.selected == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 380)
        .task { store.refresh() }
    }
}
```

- [ ] **Step 2: Create the XcodeGen spec**

Create `project.yml`:

```yaml
name: MCHOSEMac
options:
  bundleIdPrefix: local.mchose
  deploymentTarget:
    macOS: "13.0"
packages:
  MCHOSECore:
    path: .
targets:
  MCHOSEMac:
    type: application
    platform: macOS
    sources:
      - path: App/Sources
    resources:
      - path: Resources
    dependencies:
      - package: MCHOSECore
        product: HIDTransport
      - package: MCHOSECore
        product: Protocol
      - package: MCHOSECore
        product: Features
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: local.mchose.mac
        PRODUCT_NAME: MCHOSEMac
        CODE_SIGNING_ALLOWED: NO
        CODE_SIGNING_REQUIRED: NO
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.utilities
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        SWIFT_VERSION: "5.0"
```

Add to `.gitignore`:

```gitignore
MCHOSEMac.xcodeproj/
build/
DerivedData/
```

- [ ] **Step 3: Generate and build**

Run:

```bash
cd ~/mchose-mac
xcodegen generate
xcodebuild -project MCHOSEMac.xcodeproj -scheme MCHOSEMac -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

If the build fails because `DeviceStore`/views are not defined yet, that is expected; they are added in Task 7. In that case, create the files from Task 7 before building, or temporarily keep only `MCHOSEMacApp` with a placeholder `Text("MCHOSE Mac")` body. Do not commit a broken app shell.

- [ ] **Step 4: Commit**

```bash
git add project.yml App .gitignore
git commit -m "build: add XcodeGen app project"
```

---

## Task 7: Device store and views

**Files:**
- Create: `App/Sources/DeviceStore.swift`
- Create: `App/Sources/Views/ConnectionStatusView.swift`
- Create: `App/Sources/Views/DeviceListView.swift`
- Create: `App/Sources/Views/DeviceInfoView.swift`
- Create: `App/Sources/Views/MenuBarContent.swift`

**Interfaces:**
- Consumes: `HIDEnumerator`, `ManifestLoader`, `DeviceMatcher`, `DeviceConnection`
- Produces: observable app state and read-only UI

- [ ] **Step 1: Implement the store**

Create `App/Sources/DeviceStore.swift`:

```swift
import Foundation
import Combine
import AppKit
import HIDTransport
import Features

struct ConnectedDevice: Identifiable {
    let id: String
    let ref: HIDDeviceRef
    let connection: DeviceConnection

    init(ref: HIDDeviceRef, manifest: DeviceManifest) {
        self.id = "\(ref.info.identity.vendorId)-\(ref.info.identity.productId)-\(ref.info.registryId)"
        self.ref = ref
        self.connection = DeviceConnection(ref: ref, manifest: manifest)
    }
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published private(set) var devices: [ConnectedDevice] = []
    @Published private(set) var selected: ConnectedDevice?
    @Published private(set) var info: DeviceInfo?
    @Published private(set) var status: String = "未连接"
    @Published private(set) var error: String?

    private let manifest: DeviceManifest?
    private let enumerator = HIDEnumerator()

    init() {
        manifest = try? ManifestLoader.loadBundled()
    }

    func refresh() {
        error = nil
        guard let manifest else {
            status = "设备清单加载失败"
            return
        }

        let refs = enumerator.listDevices().filter {
            DeviceMatcher.matches(info: $0.info, manifest: manifest)
                && $0.info.interface.isConfigurationInterface
        }

        devices = refs.map { ConnectedDevice(ref: $0, manifest: manifest) }
        if selected == nil {
            selected = devices.first
        }
        status = devices.isEmpty ? "未连接" : "已发现 \(devices.count) 个设备"
    }

    func select(_ device: ConnectedDevice) {
        selected = device
        info = nil
    }

    func connectSelected() {
        guard let selected else { return }
        do {
            try selected.connection.connect()
            info = try selected.connection.readInfo()
            status = "已连接"
            error = nil
        } catch {
            status = "连接失败"
            self.error = error.localizedDescription
            info = nil
        }
    }

    func disconnectSelected() {
        selected?.connection.close()
        info = nil
        status = "未连接"
    }
}
```

- [ ] **Step 2: Implement the views**

Create `App/Sources/Views/ConnectionStatusView.swift`:

```swift
import SwiftUI

struct ConnectionStatusView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.status)
                .font(.subheadline.weight(.medium))
            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
```

Create `App/Sources/Views/DeviceListView.swift`:

```swift
import SwiftUI

struct DeviceListView: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        List(store.devices) { device in
            HStack {
                Text(device.ref.info.product)
                Spacer()
                Text(
                    String(
                        format: "0x%04X:0x%04X",
                        device.ref.info.identity.vendorId,
                        device.ref.info.identity.productId
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(device) }
            .background(
                store.selected?.id == device.id
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
            )
        }
        .frame(height: 120)
    }
}
```

Create `App/Sources/Views/DeviceInfoView.swift`:

```swift
import SwiftUI
import HIDTransport
import Features

struct DeviceInfoView: View {
    let info: DeviceInfo?

    var body: some View {
        if let info {
            VStack(alignment: .leading, spacing: 6) {
                Text("设备信息").font(.headline)
                Text("型号：\(info.product)")
                Text("固件构建：\(info.buildDate)")
                Text("固件版本：\(info.firmwareVersion ?? "未识别")")
                Text("Raw：\(Hex.string(info.rawPayload))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else {
            Text("连接设备后显示信息")
                .foregroundStyle(.secondary)
        }
    }
}
```

Create `App/Sources/Views/MenuBarContent.swift`:

```swift
import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var store: DeviceStore

    var body: some View {
        Text(store.status)
        Button("扫描设备") { store.refresh() }
        Button("连接") { store.connectSelected() }
        Button("断开") { store.disconnectSelected() }
        Divider()
        Button("退出") { NSApplication.shared.terminate(nil) }
    }
}
```

- [ ] **Step 3: Build**

Run:

```bash
cd ~/mchose-mac
xcodegen generate
xcodebuild -project MCHOSEMac.xcodeproj -scheme MCHOSEMac -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the app**

Run:

```bash
open ~/mchose-mac/build/Debug/MCHOSEMac.app
```

If the build output is elsewhere, use:

```bash
xcodebuild -project MCHOSEMac.xcodeproj -scheme MCHOSEMac -configuration Debug -showBuildSettings | grep TARGET_BUILD_DIR
```

- [ ] **Step 5: Commit**

```bash
git add App/Sources/DeviceStore.swift App/Sources/Views
git commit -m "feat: add device store and read-only UI"
```

---

## Task 8: Hardware acceptance

- [ ] **Step 1: Run package tests**

```bash
cd ~/mchose-mac
swift test
```

Expected: all tests PASS.

- [ ] **Step 2: Launch the app with the keyboard connected**

```bash
open ~/mchose-mac/build/Debug/MCHOSEMac.app
```

Expected:

1. The device list shows `Ace 68 Turbo 16K`.
2. Clicking 连接 shows `已连接`.
3. Device info shows the build date `Jul 21 2026,15:16:19`.
4. No settings are written; the keyboard remains usable.

- [ ] **Step 3: Verify read-only safety**

```bash
grep -RIn "setOutputReport" ../mchose-mac/Sources ../mchose-mac/App
```

Expected: only `HIDDeviceHandle.setOutputReport` and `CZSession.getInfo`'s request call. No Set/Reset/OTA commands.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: complete Phase 1a read-only app"
```

---

## Phase 1a Exit Criteria

- [ ] `swift test` passes.
- [ ] Xcode app builds with `xcodebuild`.
- [ ] App lists `Ace 68 Turbo 16K`.
- [ ] App connects and displays product/build date.
- [ ] No write command exists in the app path.
- [ ] Phase 1b can build on `DeviceConnection` and `DeviceStore` without restructuring.

---

## Execution Notes (2026-10-18)

- XcodeGen ignored the target-level `resources:` key in this setup. The manifest is included with:
  `sources: - path: Resources/DeviceManifests, type: folder`.
- The app auto-connects the first matching device during the first scan; the 连接 button remains for manual reconnect.
- The built app is symlinked to `~/mchose-mac/build/MCHOSEMac.app`.
- Verified app data path: manifest loaded `Ace 68 Turbo 16K`; scan found 1 device; auto-connect returned `firmware=126` and `build=Jul 21 2026,15:16:19`.
- UI text inspection through System Events is blocked by macOS Accessibility permission. The app process is running and the data path is verified; visual inspection is left to the user.
- Package tests: 6 Protocol + 14 HIDTransport + 4 Features, all passing.

