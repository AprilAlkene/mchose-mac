# MCHOSE Mac Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a read-only Swift CLI that enumerates the MCHOSE keyboard, opens its 64-byte vendor HID interface, captures CZ protocol frames from the official web driver, and reads device identity/version without writing to the device.

**Architecture:** SwiftPM package with three targets: `HIDTransport` (IOKit enumeration/open/report I/O), `Protocol` (CZ frame codec), and `MCHOSECLI` (diagnostic commands). Phase 0 is a hard gate: no UI, no settings writes, no OTA, no boot-mode transitions. Every protocol decision is validated against frames captured from the official web driver.

**Tech Stack:** Swift 5.9+, SwiftPM, IOKit.hid, XCTest, Python 3 (manifest extraction), Microsoft Edge DevTools (frame capture).

**Spec:** `docs/superpowers/specs/2026-10-18-mchose-mac-design.md`

## Global Constraints

- macOS 13+, Apple Silicon.
- No third-party Swift dependencies.
- Phase 0 is read-only: never send `Set`, `Reset`, OTA, or boot-mode commands.
- Configuration interface: `usagePage 0x01 / usage 0x00`, or boot `0xFF00 / 0x01`; vendor interface is 64-byte IN/OUT.
- Verified device: VID `0x3837`, PID `0x3026`; boot PID `0x3027`.
- Standard keyboard interfaces (`usage 0x06`) must not be opened or written.
- Commit after every task; do not commit `.build/`.
- If a device command fails, log the raw hex and stop; never retry with guessed bytes.

## Test Harness Adaptation (this machine)

This Mac has Command Line Tools only; XCTest is not installed. Tests use **Swift Testing** instead:

- `import Testing`, `@Test func name()`, `#expect(condition)`, `#expect(value == expected)`
- `Package.swift` test targets load `libTestingMacros.dylib` and add rpaths for `Testing.framework` and `lib_TestingInterop.dylib`
- Where a step below shows XCTest code, translate it to the equivalent Swift Testing assertion. The test names and expected behavior stay the same.

## Execution Notes (2026-10-18)

- Task 6 was completed without the manual UI capture flow. The CZ SDK exposed on the page (`CZ_SHARED_DATA.createDeviceSDK`) was used to emit the `getInfo` request; the real-device response was captured over WebHID, then reproduced natively.
- Captured frames are in `docs/captures/ace68-phase0.md`; the test fixture is `Tests/ProtocolTests/Fixtures/ace68-read-info.json`.
- Command `0x03` showed no checksum in the captured request or response. The codec implements the observed 8-byte header plus 64-byte zero padding instead of the earlier guessed packet/checksum layout.
- IOKit input callbacks require `IOHIDDeviceScheduleWithRunLoop` on the current run loop; without it the request is sent but the response is never delivered.
- `mchose-cli info 0` returned the same response as the web SDK, including the firmware build date `Jul 21 2026,15:16:19`.


---

## File Structure

```text
~/mchose-mac/
  Package.swift
  Sources/
    HIDTransport/
      HIDDeviceIdentity.swift
      HIDInterfaceDescriptor.swift
      HIDDeviceInfo.swift
      HIDDeviceRef.swift
      HIDEnumerator.swift
      HIDError.swift
      HIDDeviceHandle.swift
      Hex.swift
    Protocol/
      ProtocolVersion.swift
      CZCodec.swift
      CZSession.swift
    MCHOSECLI/
      main.swift
  Tests/
    HIDTransportTests/
      HIDDeviceIdentityTests.swift
      HIDInterfaceDescriptorTests.swift
      HIDDeviceInfoTests.swift
      HIDEnumeratorTests.swift
      HIDErrorTests.swift
      HexTests.swift
    ProtocolTests/
      ProtocolVersionTests.swift
      CZCodecTests.swift
      Fixtures/
        ace68-read-info.json
  Tools/
    extract-manifest/
      extract.py
      test_extract.py
      fixtures/
        ace68_snippet.txt
  Resources/
    DeviceManifests/
      ace68_turbo_16k.json
  docs/
    captures/
      ace68-phase0.md
    superpowers/
      specs/2026-10-18-mchose-mac-design.md
      plans/2026-10-18-mchose-mac-phase0.md
```

---

## Task 1: Bootstrap the Swift package and identity model

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/HIDTransport/HIDDeviceIdentity.swift`
- Create: `Sources/MCHOSECLI/main.swift`
- Test: `Tests/HIDTransportTests/HIDDeviceIdentityTests.swift`

**Interfaces:**
- Produces: `HIDDeviceIdentity(vendorId:productId:)`, `HIDDeviceIdentity.isSupportedVendor: Bool`, `HIDDeviceIdentity.supportedVendorIds: Set<Int>`

- [ ] **Step 1: Initialize the repository and directories**

Run:

```bash
cd ~/mchose-mac
git init
mkdir -p Sources/HIDTransport Sources/Protocol Sources/MCHOSECLI \
  Tests/HIDTransportTests Tests/ProtocolTests/Fixtures \
  Tools/extract-manifest/fixtures Resources/DeviceManifests docs/captures
```

Create `.gitignore`:

```gitignore
.build/
.swiftpm/
.DS_Store
*.xcuserstate
```

- [ ] **Step 2: Write the failing test**

Create `Tests/HIDTransportTests/HIDDeviceIdentityTests.swift`:

```swift
import XCTest
@testable import HIDTransport

final class HIDDeviceIdentityTests: XCTestCase {
    func testSupportedVendors() {
        XCTAssertTrue(HIDDeviceIdentity(vendorId: 0x3837, productId: 0x3026).isSupportedVendor)
        XCTAssertTrue(HIDDeviceIdentity(vendorId: 0x19F5, productId: 0xFC30).isSupportedVendor)
        XCTAssertTrue(HIDDeviceIdentity(vendorId: 0x41E4, productId: 0x2102).isSupportedVendor)
    }

    func testUnknownVendor() {
        XCTAssertFalse(HIDDeviceIdentity(vendorId: 0x1234, productId: 0x5678).isSupportedVendor)
    }
}
```

- [ ] **Step 3: Create the package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MCHOSEMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HIDTransport", targets: ["HIDTransport"]),
        .library(name: "Protocol", targets: ["Protocol"]),
        .executable(name: "mchose-cli", targets: ["MCHOSECLI"]),
    ],
    targets: [
        .target(
            name: "HIDTransport",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(name: "Protocol", dependencies: ["HIDTransport"]),
        .executableTarget(name: "MCHOSECLI", dependencies: ["HIDTransport", "Protocol"]),
        .testTarget(name: "HIDTransportTests", dependencies: ["HIDTransport"]),
        .testTarget(name: "ProtocolTests", dependencies: ["Protocol", "HIDTransport"]),
    ]
)
```

Create `Sources/MCHOSECLI/main.swift`:

```swift
import Foundation

print("mchose-cli <list|open|monitor|info>")
```

Create empty implementation file `Sources/HIDTransport/HIDDeviceIdentity.swift`:

```swift
public struct HIDDeviceIdentity: Equatable, Sendable {
    public let vendorId: Int
    public let productId: Int

    public init(vendorId: Int, productId: Int) {
        self.vendorId = vendorId
        self.productId = productId
    }

    public static let supportedVendorIds: Set<Int> = []

    public var isSupportedVendor: Bool { false }
}
```

Create `Sources/Protocol/ProtocolVersion.swift` so the Protocol target has a real source file:

```swift
public enum ProtocolVersion {
    public static let current = 1
}
```

Create `Tests/ProtocolTests/ProtocolVersionTests.swift` so the test target has a real test file:

```swift
import XCTest
@testable import Protocol

final class ProtocolVersionTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(ProtocolVersion.current, 1)
    }
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run:

```bash
cd ~/mchose-mac
swift test --filter HIDDeviceIdentityTests
```

Expected: FAIL, because `isSupportedVendor` is always `false`.

- [ ] **Step 5: Implement the identity model**

Replace `Sources/HIDTransport/HIDDeviceIdentity.swift`:

```swift
public struct HIDDeviceIdentity: Equatable, Sendable {
    public let vendorId: Int
    public let productId: Int

    public init(vendorId: Int, productId: Int) {
        self.vendorId = vendorId
        self.productId = productId
    }

    public static let supportedVendorIds: Set<Int> = [0x19F5, 0x3837, 0x41E4]

    public var isSupportedVendor: Bool {
        Self.supportedVendorIds.contains(vendorId)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
swift test --filter HIDDeviceIdentityTests
swift run mchose-cli
```

Expected: tests PASS; CLI prints `mchose-cli <list|open|monitor|info>`.

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "chore: bootstrap Swift package and device identity"
```

---

## Task 2: Select the vendor configuration interface

**Files:**
- Create: `Sources/HIDTransport/HIDInterfaceDescriptor.swift`
- Test: `Tests/HIDTransportTests/HIDInterfaceDescriptorTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces: `HIDInterfaceDescriptor(usagePage:usage:maxInputReportSize:maxOutputReportSize:)`, `.isConfigurationInterface: Bool`

- [ ] **Step 1: Write the failing test**

Create `Tests/HIDTransportTests/HIDInterfaceDescriptorTests.swift`:

```swift
import XCTest
@testable import HIDTransport

final class HIDInterfaceDescriptorTests: XCTestCase {
    func testNormalConfigurationInterface() {
        let descriptor = HIDInterfaceDescriptor(
            usagePage: 0x01, usage: 0x00,
            maxInputReportSize: 64, maxOutputReportSize: 64
        )
        XCTAssertTrue(descriptor.isConfigurationInterface)
    }

    func testBootConfigurationInterface() {
        let descriptor = HIDInterfaceDescriptor(
            usagePage: 0xFF00, usage: 0x01,
            maxInputReportSize: 64, maxOutputReportSize: 64
        )
        XCTAssertTrue(descriptor.isConfigurationInterface)
    }

    func testKeyboardInterfaceIsRejected() {
        let descriptor = HIDInterfaceDescriptor(
            usagePage: 0x01, usage: 0x06,
            maxInputReportSize: 16, maxOutputReportSize: 1
        )
        XCTAssertFalse(descriptor.isConfigurationInterface)
    }

    func testSmallVendorInterfaceIsRejected() {
        let descriptor = HIDInterfaceDescriptor(
            usagePage: 0x01, usage: 0x00,
            maxInputReportSize: 8, maxOutputReportSize: 1
        )
        XCTAssertFalse(descriptor.isConfigurationInterface)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter HIDInterfaceDescriptorTests
```

Expected: FAIL, `HIDInterfaceDescriptor` is not defined.

- [ ] **Step 3: Implement the descriptor**

Create `Sources/HIDTransport/HIDInterfaceDescriptor.swift`:

```swift
public struct HIDInterfaceDescriptor: Equatable, Sendable {
    public let usagePage: Int
    public let usage: Int
    public let maxInputReportSize: Int
    public let maxOutputReportSize: Int

    public init(
        usagePage: Int,
        usage: Int,
        maxInputReportSize: Int,
        maxOutputReportSize: Int
    ) {
        self.usagePage = usagePage
        self.usage = usage
        self.maxInputReportSize = maxInputReportSize
        self.maxOutputReportSize = maxOutputReportSize
    }

    public var isConfigurationInterface: Bool {
        let isNormal = usagePage == 0x01 && usage == 0x00
        let isBoot = usagePage == 0xFF00 && usage == 0x01
        return (isNormal || isBoot) && maxOutputReportSize >= 32
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --filter HIDInterfaceDescriptorTests
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/HIDTransport/HIDInterfaceDescriptor.swift Tests/HIDTransportTests/HIDInterfaceDescriptorTests.swift
git commit -m "feat: identify vendor configuration HID interface"
```

---

## Task 3: Map IOKit properties to DeviceInfo

**Files:**
- Create: `Sources/HIDTransport/HIDDeviceInfo.swift`
- Test: `Tests/HIDTransportTests/HIDDeviceInfoTests.swift`

**Interfaces:**
- Consumes: `HIDDeviceIdentity`, `HIDInterfaceDescriptor`
- Produces: `HIDDeviceInfo(properties: [String: Any])?`, fields `product`, `identity`, `interface`, `transport`, `registryId`

- [ ] **Step 1: Write the failing test**

Create `Tests/HIDTransportTests/HIDDeviceInfoTests.swift`:

```swift
import XCTest
@testable import HIDTransport

final class HIDDeviceInfoTests: XCTestCase {
    func testMapsConfigurationInterfaceProperties() {
        let properties: [String: Any] = [
            "Product": "Ace 68 Turbo 16K",
            "VendorID": 0x3837,
            "ProductID": 0x3026,
            "PrimaryUsagePage": 0x01,
            "PrimaryUsage": 0x00,
            "MaxInputReportSize": 64,
            "MaxOutputReportSize": 64,
            "Transport": "USB",
            "RegistryID": 0x100004FD4 as UInt64,
        ]

        let info = HIDDeviceInfo(properties: properties)

        XCTAssertEqual(info?.product, "Ace 68 Turbo 16K")
        XCTAssertEqual(info?.identity.vendorId, 0x3837)
        XCTAssertEqual(info?.identity.productId, 0x3026)
        XCTAssertEqual(info?.interface.isConfigurationInterface, true)
        XCTAssertEqual(info?.transport, "USB")
        XCTAssertEqual(info?.registryId, 0x100004FD4)
    }

    func testRejectsIncompleteProperties() {
        let properties: [String: Any] = ["Product": "Ace 68 Turbo 16K"]
        XCTAssertNil(HIDDeviceInfo(properties: properties))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter HIDDeviceInfoTests
```

Expected: FAIL, `HIDDeviceInfo` is not defined.

- [ ] **Step 3: Implement the mapping**

Create `Sources/HIDTransport/HIDDeviceInfo.swift`:

```swift
public struct HIDDeviceInfo: Equatable, Sendable {
    public let product: String
    public let identity: HIDDeviceIdentity
    public let interface: HIDInterfaceDescriptor
    public let transport: String
    public let registryId: UInt64

    public init?(properties: [String: Any]) {
        guard
            let product = properties["Product"] as? String,
            let vendorId = Self.intValue(properties["VendorID"]),
            let productId = Self.intValue(properties["ProductID"]),
            let usagePage = Self.intValue(properties["PrimaryUsagePage"]),
            let usage = Self.intValue(properties["PrimaryUsage"]),
            let maxInput = Self.intValue(properties["MaxInputReportSize"]),
            let maxOutput = Self.intValue(properties["MaxOutputReportSize"])
        else {
            return nil
        }

        self.product = product
        self.identity = HIDDeviceIdentity(vendorId: vendorId, productId: productId)
        self.interface = HIDInterfaceDescriptor(
            usagePage: usagePage,
            usage: usage,
            maxInputReportSize: maxInput,
            maxOutputReportSize: maxOutput
        )
        self.transport = properties["Transport"] as? String ?? "Unknown"
        self.registryId = Self.uint64Value(properties["RegistryID"]) ?? 0
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func uint64Value(_ value: Any?) -> UInt64? {
        if let value = value as? UInt64 { return value }
        if let value = value as? NSNumber { return value.uint64Value }
        return nil
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --filter HIDDeviceInfoTests
```

Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/HIDTransport/HIDDeviceInfo.swift Tests/HIDTransportTests/HIDDeviceInfoTests.swift
git commit -m "feat: map IOKit properties to device info"
```

---

## Task 4: Enumerate devices and add the `list` command

**Files:**
- Create: `Sources/HIDTransport/HIDDeviceRef.swift`
- Create: `Sources/HIDTransport/HIDEnumerator.swift`
- Modify: `Sources/MCHOSECLI/main.swift`
- Test: `Tests/HIDTransportTests/HIDEnumeratorTests.swift`

**Interfaces:**
- Consumes: `HIDDeviceInfo`, `HIDDeviceIdentity`
- Produces: `HIDDeviceRef.info`, `HIDDeviceRef.device`, `HIDEnumerator.listDevices() -> [HIDDeviceRef]`, `HIDEnumerator.configurationInfos(from:) -> [HIDDeviceInfo]`

- [ ] **Step 1: Write the failing test**

Create `Tests/HIDTransportTests/HIDEnumeratorTests.swift`:

```swift
import XCTest
@testable import HIDTransport

final class HIDEnumeratorTests: XCTestCase {
    func testKeepsOnlyConfigurationInterfaces() {
        let config = HIDInterfaceDescriptor(
            usagePage: 0x01, usage: 0x00,
            maxInputReportSize: 64, maxOutputReportSize: 64
        )
        let keyboard = HIDInterfaceDescriptor(
            usagePage: 0x01, usage: 0x06,
            maxInputReportSize: 16, maxOutputReportSize: 1
        )

        let infos = [
            HIDDeviceInfo(testProduct: "Ace 68 Turbo 16K", interface: config),
            HIDDeviceInfo(testProduct: "Ace 68 Turbo 16K", interface: keyboard),
        ]

        let result = HIDEnumerator.configurationInfos(from: infos)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].interface.isConfigurationInterface)
    }
}

private extension HIDDeviceInfo {
    init(testProduct: String, interface: HIDInterfaceDescriptor) {
        self.init(
            product: testProduct,
            identity: HIDDeviceIdentity(vendorId: 0x3837, productId: 0x3026),
            interface: interface,
            transport: "USB",
            registryId: 0
        )
    }
}
```

Add a public memberwise initializer to `HIDDeviceInfo` in Step 3 so the test compiles:

```swift
public init(
    product: String,
    identity: HIDDeviceIdentity,
    interface: HIDInterfaceDescriptor,
    transport: String,
    registryId: UInt64
) {
    self.product = product
    self.identity = identity
    self.interface = interface
    self.transport = transport
    self.registryId = registryId
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter HIDEnumeratorTests
```

Expected: FAIL, `HIDEnumerator` is not defined.

- [ ] **Step 3: Implement the enumerator and list command**

Update `Sources/HIDTransport/HIDDeviceInfo.swift` by adding the public memberwise initializer shown in Step 1.

Create `Sources/HIDTransport/HIDDeviceRef.swift`:

```swift
import IOKit.hid

public final class HIDDeviceRef {
    public let info: HIDDeviceInfo
    public let device: IOHIDDevice

    public init(info: HIDDeviceInfo, device: IOHIDDevice) {
        self.info = info
        self.device = device
    }
}
```

Create `Sources/HIDTransport/HIDEnumerator.swift`:

```swift
import IOKit.hid

public final class HIDEnumerator {
    private static let propertyKeys = [
        "Product",
        "VendorID",
        "ProductID",
        "PrimaryUsagePage",
        "PrimaryUsage",
        "MaxInputReportSize",
        "MaxOutputReportSize",
        "Transport",
        "RegistryID",
    ]

    public init() {}

    public func listDevices() -> [HIDDeviceRef] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)

        guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return []
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return devices.compactMap { device in
            var properties: [String: Any] = [:]
            for key in Self.propertyKeys {
                if let value = IOHIDDeviceGetProperty(device, key as CFString) {
                    properties[key] = value
                }
            }
            guard let info = HIDDeviceInfo(properties: properties) else { return nil }
            return HIDDeviceRef(info: info, device: device)
        }
    }

    public static func configurationInfos(from infos: [HIDDeviceInfo]) -> [HIDDeviceInfo] {
        infos.filter { $0.interface.isConfigurationInterface }
    }
}
```

Replace `Sources/MCHOSECLI/main.swift`:

```swift
import Foundation
import HIDTransport

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

switch command {
case "list":
    let refs = HIDEnumerator().listDevices().filter {
        $0.info.identity.isSupportedVendor && $0.info.interface.isConfigurationInterface
    }
    if refs.isEmpty {
        print("No MCHOSE configuration interface found.")
    } else {
        for ref in refs {
            let info = ref.info
            print(
                "\(info.product) vid=0x\(String(info.identity.vendorId, radix: 16)) " +
                "pid=0x\(String(info.identity.productId, radix: 16)) " +
                "usagePage=0x\(String(info.interface.usagePage, radix: 16)) " +
                "usage=0x\(String(info.interface.usage, radix: 16)) " +
                "in=\(info.interface.maxInputReportSize) out=\(info.interface.maxOutputReportSize) " +
                "transport=\(info.transport)"
            )
        }
    }
default:
    print("mchose-cli <list|open|monitor|info>")
}
```

- [ ] **Step 4: Run the tests and the hardware list command**

Run:

```bash
swift test --filter HIDEnumeratorTests
swift run mchose-cli list
```

Expected: test PASS; `list` prints a line containing `Ace 68 Turbo 16K`, `vid=0x3837`, `pid=0x3026`, `usagePage=0x1`, `usage=0x0`, `in=64 out=64`.

If the device is not connected, the command prints `No MCHOSE configuration interface found.` — reconnect and rerun.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: enumerate MCHOSE configuration interfaces"
```

---

## Task 5: Open the interface and map IOKit errors

**Files:**
- Create: `Sources/HIDTransport/HIDError.swift`
- Create: `Sources/HIDTransport/HIDDeviceHandle.swift`
- Create: `Sources/HIDTransport/Hex.swift`
- Modify: `Sources/MCHOSECLI/main.swift`
- Test: `Tests/HIDTransportTests/HIDErrorTests.swift`
- Test: `Tests/HIDTransportTests/HexTests.swift`

**Interfaces:**
- Consumes: `HIDDeviceRef`
- Produces: `HIDDeviceHandle(device: IOHIDDevice)`, `.open() throws`, `.close()`, `.setOutputReport(reportId:bytes:) throws`, `.startInputReports(_:) throws`, `.stopInputReports()`, `HIDError`, `Hex.string(_:)`, `Hex.parse(_:)`

- [ ] **Step 1: Write the failing tests**

Create `Tests/HIDTransportTests/HIDErrorTests.swift`:

```swift
import XCTest
import IOKit
@testable import HIDTransport

final class HIDErrorTests: XCTestCase {
    func testNotPermittedDescriptionContainsHexCode() {
        let error = HIDError.ioKit(kIOReturnNotPermitted)
        XCTAssertTrue(error.localizedDescription.contains("0xE00002E2"))
        XCTAssertTrue(error.localizedDescription.lowercased().contains("protected"))
    }

    func testNotFoundDescription() {
        XCTAssertEqual(HIDError.notFound.localizedDescription, "MCHOSE configuration interface not found")
    }
}
```

Create `Tests/HIDTransportTests/HexTests.swift`:

```swift
import XCTest
@testable import HIDTransport

final class HexTests: XCTestCase {
    func testFormat() {
        XCTAssertEqual(Hex.string([0x00, 0x0A, 0xFF]), "00 0A FF")
    }

    func testParse() {
        XCTAssertEqual(Hex.parse("00 0a ff"), [0x00, 0x0A, 0xFF])
    }

    func testParseRejectsOddLength() {
        XCTAssertNil(Hex.parse("0A F"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter HIDErrorTests
swift test --filter HexTests
```

Expected: FAIL, types are not defined.

- [ ] **Step 3: Implement error mapping, hex utilities, and the device handle**

Create `Sources/HIDTransport/HIDError.swift`:

```swift
import Foundation
import IOKit

public enum HIDError: Error, Equatable, LocalizedError {
    case notFound
    case openFailed(IOReturn)
    case ioKit(IOReturn)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "MCHOSE configuration interface not found"
        case .openFailed(let code), .ioKit(let code):
            let hex = String(format: "0x%08X", UInt32(bitPattern: code))
            if code == kIOReturnNotPermitted {
                return "IOKit error \(hex): interface is protected or permission is denied"
            }
            return "IOKit error \(hex)"
        case .invalidResponse:
            return "Invalid device response"
        }
    }
}
```

Create `Sources/HIDTransport/Hex.swift`:

```swift
public enum Hex {
    public static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func parse(_ string: String) -> [UInt8]? {
        let parts = string.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        guard !parts.isEmpty else { return [] }
        var result: [UInt8] = []
        for part in parts {
            guard part.count == 2, let value = UInt8(part, radix: 16) else { return nil }
            result.append(value)
        }
        return result
    }
}
```

Create `Sources/HIDTransport/HIDDeviceHandle.swift`:

```swift
import Foundation
import IOKit.hid

public final class HIDDeviceHandle {
    private let device: IOHIDDevice
    private var isOpen = false
    private var inputBuffer: UnsafeMutablePointer<UInt8>?
    private var onInput: ((UInt8, [UInt8]) -> Void)?

    public init(device: IOHIDDevice) {
        self.device = device
    }

    deinit {
        stopInputReports()
        close()
    }

    public func open() throws {
        guard !isOpen else { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw HIDError.openFailed(result)
        }
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
    }

    public func setOutputReport(reportId: UInt32, bytes: [UInt8]) throws {
        guard isOpen, !bytes.isEmpty else {
            throw HIDError.notFound
        }
        let result = bytes.withUnsafeBufferPointer { buffer -> IOReturn in
            IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                CFIndex(reportId),
                buffer.baseAddress!,
                buffer.count
            )
        }
        guard result == kIOReturnSuccess else {
            throw HIDError.ioKit(result)
        }
    }

    public func startInputReports(_ handler: @escaping (UInt8, [UInt8]) -> Void) throws {
        guard isOpen else {
            throw HIDError.notFound
        }
        stopInputReports()

        let size = 64
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
        inputBuffer = buffer
        onInput = handler

        IOHIDDeviceRegisterInputReportCallback(
            device,
            buffer,
            size,
            mchoseInputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    public func stopInputReports() {
        onInput = nil
        if let buffer = inputBuffer {
            IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
            buffer.deinitialize(count: 64)
            buffer.deallocate()
            inputBuffer = nil
        }
    }

    fileprivate func handleInput(reportId: UInt32, bytes: [UInt8]) {
        onInput?(UInt8(truncatingIfNeeded: reportId), bytes)
    }
}

private func mchoseInputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportId: UInt32,
    report: UnsafePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context else { return }
    let handle = Unmanaged<HIDDeviceHandle>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    handle.handleInput(reportId: reportId, bytes: bytes)
}
```

Update `Sources/MCHOSECLI/main.swift`:

```swift
import Foundation
import HIDTransport

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"

func configurationRef() -> HIDDeviceRef? {
    HIDEnumerator().listDevices().first {
        $0.info.identity.isSupportedVendor && $0.info.interface.isConfigurationInterface
    }
}

switch command {
case "list":
    let refs = HIDEnumerator().listDevices().filter {
        $0.info.identity.isSupportedVendor && $0.info.interface.isConfigurationInterface
    }
    if refs.isEmpty {
        print("No MCHOSE configuration interface found.")
    } else {
        for ref in refs {
            let info = ref.info
            print(
                "\(info.product) vid=0x\(String(info.identity.vendorId, radix: 16)) " +
                "pid=0x\(String(info.identity.productId, radix: 16)) " +
                "usagePage=0x\(String(info.interface.usagePage, radix: 16)) " +
                "usage=0x\(String(info.interface.usage, radix: 16)) " +
                "in=\(info.interface.maxInputReportSize) out=\(info.interface.maxOutputReportSize) " +
                "transport=\(info.transport)"
            )
        }
    }

case "open":
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    let handle = HIDDeviceHandle(device: ref.device)
    do {
        try handle.open()
        print("open=0x0 \(ref.info.product)")
        handle.close()
    } catch {
        print("open failed: \(error.localizedDescription)")
        exit(1)
    }

case "monitor":
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    let handle = HIDDeviceHandle(device: ref.device)
    do {
        try handle.open()
        try handle.startInputReports { reportId, bytes in
            print("report=0x\(String(reportId, radix: 16)) \(Hex.string(bytes))")
        }
        print("monitoring for 10 seconds; send a read command from the web driver or CLI to see input reports")
        RunLoop.current.run(until: Date().addingTimeInterval(10))
        handle.stopInputReports()
        handle.close()
    } catch {
        print("monitor failed: \(error.localizedDescription)")
        exit(1)
    }

default:
    print("mchose-cli <list|open|monitor|info>")
}
```

- [ ] **Step 4: Run tests and the hardware open command**

Run:

```bash
swift test --filter HIDErrorTests
swift test --filter HexTests
swift run mchose-cli open
```

Expected: tests PASS; `open` prints `open=0x0 Ace 68 Turbo 16K`.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: open vendor HID interface and expose read-only report I/O"
```

---

## Task 6: Capture CZ protocol frames from the web driver

**Files:**
- Create: `docs/captures/ace68-phase0.md`

**Interfaces:**
- Produces: documented request/response hex frames used by Task 7 and Task 8

- [ ] **Step 1: Open the web driver in Edge with DevTools**

Run:

```bash
open -a "Microsoft Edge" "https://www.mchose.com.cn/#/connectDevice"
```

In Edge: `View → Developer → Developer Tools` (or `Option+Command+I`), select the **Console** tab, and clear it.

- [ ] **Step 2: Connect the device and start a read action**

1. Click the page's connect button.
2. In the device picker, select `Ace 68 Turbo 16K`.
3. Wait for the device page to load.
4. Click only read-only UI actions: device info, current settings, keymap view, lighting view.
5. Do **not** click apply/save/reset/firmware update.

- [ ] **Step 3: Copy the HID logs**

The page installs a HID logger (`installHidSendLogger`). In the Console, filter with `webHID`. Copy every line matching:

- `[webHID:发送]`
- `[webHID:接收Input]`
- `[webHID:接收Feature]`

Write them into `docs/captures/ace68-phase0.md` using this exact format:

```markdown
# Ace 68 Turbo 16K — Phase 0 capture

- Date:
- Edge version:
- Device firmware (from web UI, if shown):
- Report ID used by the web app:

## Read device info

### Request
```text
[webHID:发送] reportId=... payload=...
```

### Response
```text
[webHID:接收Input] reportId=... payload=...
```

## Read current settings

### Request
```text
...
```

### Response
```text
...
```
```

- [ ] **Step 4: Record the minimum accepted dataset**

The capture is complete when it contains at least:

1. One request that reads device identity/version.
2. Its matching response.
3. The report ID used for both.
4. The exact byte layout of the response header and payload.

If the console shows no HID logs, run this in the Console after connecting and paste the output into the capture file:

```javascript
(async () => {
  const devices = await navigator.hid.getDevices();
  console.log(devices.map(d => ({
    product: d.productName,
    vendorId: d.vendorId,
    productId: d.productId,
    collections: d.collections
  })));
})();
```

- [ ] **Step 5: Create the protocol fixture from the capture**

Create `Tests/ProtocolTests/Fixtures/ace68-read-info.json` using the exact captured values:

```json
{
  "reportId": 0,
  "requestHex": "<paste the request payload hex here>",
  "responseHex": "<paste the response payload hex here>",
  "commandType": 0,
  "command": 0,
  "payloadHex": "<paste the request payload bytes only>"
}
```

Every field except `reportId` must come from the capture; `reportId` must be the actual report ID shown in the log. Do not commit this file with angle-bracket text.

- [ ] **Step 6: Commit the capture and fixture**

```bash
git add docs/captures/ace68-phase0.md Tests/ProtocolTests/Fixtures/ace68-read-info.json
git commit -m "docs: capture Phase 0 CZ frames from web driver"
```

---

## Task 7: Implement the CZ codec against captured frames

**Files:**
- Create: `Sources/Protocol/CZCodec.swift`
- Test: `Tests/ProtocolTests/CZCodecTests.swift`
- Fixture: `Tests/ProtocolTests/Fixtures/ace68-read-info.json` (created in Task 6)

**Interfaces:**
- Consumes: captured frames from Task 6
- Produces: `CZPacket`, `CZCodec(checksum:)`, `CZCodec.encode(commandType:command:payload:reportId:maxPacketSize:) -> [[UInt8]]`, `CZCodec.decode(packet:reportId:) throws -> CZPacket`, `CZChecksum.sumWithReportId`, `CZChecksum.crc8(poly:initial:)`, `CZChecksum.crc16LowByte(poly:initial:)`, `CZChecksum.crc16HighByte(poly:initial:)`

- [ ] **Step 1: Confirm the fixture from Task 6**

Run:

```bash
cd ~/mchose-mac
cat Tests/ProtocolTests/Fixtures/ace68-read-info.json
```

Expected: the file contains non-zero `requestHex` and `responseHex`, plus the captured `reportId`, `commandType`, `command`, and `payloadHex`. If any field still contains angle brackets, return to Task 6 and complete the capture.

- [ ] **Step 2: Write the failing tests**

Create `Tests/ProtocolTests/CZCodecTests.swift`:

```swift
import XCTest
@testable import Protocol
@testable import HIDTransport

final class CZCodecTests: XCTestCase {
    private func loadFixture() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ace68-read-info.json")
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testDecodeCapturedRequest() throws {
        let fixture = try loadFixture()
        let bytes = Hex.parse(fixture["requestHex"] as! String)!
        let reportId = UInt8(fixture["reportId"] as! Int)

        // After Step 5, replace this default with the confirmed checksum candidate.
        let codec = CZCodec()
        let packet = try codec.decode(packet: bytes, reportId: reportId)

        XCTAssertEqual(packet.commandType, UInt8(fixture["commandType"] as! Int))
        XCTAssertEqual(packet.command, UInt8(fixture["command"] as! Int))
        XCTAssertEqual(Hex.string(packet.payload), fixture["payloadHex"] as! String)
    }

    func testChecksumCandidates() throws {
        let fixture = try loadFixture()
        let bytes = Hex.parse(fixture["requestHex"] as! String)!
        let body = Array(bytes.dropLast())
        let expected = bytes.last!
        let reportId = UInt8(fixture["reportId"] as! Int)

        let candidates: [(String, UInt8)] = [
            ("sum", CZChecksum.sumWithReportId(body, reportId)),
            ("crc8-07-00", CZChecksum.crc8(poly: 0x07, initial: 0x00)(body, reportId)),
            ("crc8-07-FF", CZChecksum.crc8(poly: 0x07, initial: 0xFF)(body, reportId)),
            ("crc16-1021-low", CZChecksum.crc16LowByte(poly: 0x1021, initial: 0xFFFF)(body, reportId)),
            ("crc16-1021-high", CZChecksum.crc16HighByte(poly: 0x1021, initial: 0xFFFF)(body, reportId)),
            ("crc16-8005-low", CZChecksum.crc16LowByte(poly: 0x8005, initial: 0x0000)(body, reportId)),
        ]

        print(candidates)
        XCTAssertTrue(
            candidates.contains { $0.1 == expected },
            "no checksum candidate matched 0x\(String(expected, radix: 16)): \(candidates)"
        )
    }

    func testRoundTrip() throws {
        let packet = CZPacket(
            commandType: 0x01,
            command: 0x03,
            packetCount: 1,
            packetIndex: 0,
            payload: [0xAA, 0x55]
        )
        let encoded = CZCodec().encode(
            commandType: packet.commandType,
            command: packet.command,
            payload: packet.payload,
            reportId: 0,
            maxPacketSize: 64
        )
        XCTAssertEqual(encoded.count, 1)
        let decoded = try CZCodec().decode(packet: encoded[0], reportId: 0)
        XCTAssertEqual(decoded.commandType, packet.commandType)
        XCTAssertEqual(decoded.command, packet.command)
        XCTAssertEqual(decoded.payload, packet.payload)
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run:

```bash
swift test --filter CZCodecTests
```

Expected: FAIL, `CZPacket`/`CZCodec`/`CZChecksum` are not defined.

- [ ] **Step 4: Implement the codec and checksum candidates**

Create `Sources/Protocol/CZCodec.swift`:

```swift
import Foundation
import HIDTransport

public struct CZPacket: Equatable, Sendable {
    public let commandType: UInt8
    public let command: UInt8
    public let packetCount: UInt8
    public let packetIndex: UInt8
    public let payload: [UInt8]

    public init(
        commandType: UInt8,
        command: UInt8,
        packetCount: UInt8,
        packetIndex: UInt8,
        payload: [UInt8]
    ) {
        self.commandType = commandType
        self.command = command
        self.packetCount = packetCount
        self.packetIndex = packetIndex
        self.payload = payload
    }
}

public enum CZChecksum {
    public static func sumWithReportId(_ bytes: [UInt8], _ reportId: UInt8) -> UInt8 {
        let sum = bytes.reduce(UInt16(reportId)) { partial, byte in
            partial + UInt16(byte)
        }
        return UInt8(truncatingIfNeeded: sum)
    }

    public static func crc8(poly: UInt8, initial: UInt8) -> ([UInt8], UInt8) -> UInt8 {
        { bytes, _ in
            var crc = initial
            for byte in bytes {
                crc ^= byte
                for _ in 0..<8 {
                    crc = (crc & 0x80) != 0 ? (crc << 1) ^ poly : (crc << 1)
                }
            }
            return crc
        }
    }

    public static func crc16LowByte(poly: UInt16, initial: UInt16) -> ([UInt8], UInt8) -> UInt8 {
        { bytes, _ in
            UInt8(truncatingIfNeeded: crc16(bytes: bytes, poly: poly, initial: initial))
        }
    }

    public static func crc16HighByte(poly: UInt16, initial: UInt16) -> ([UInt8], UInt8) -> UInt8 {
        { bytes, _ in
            UInt8(truncatingIfNeeded: crc16(bytes: bytes, poly: poly, initial: initial) >> 8)
        }
    }

    private static func crc16(bytes: [UInt8], poly: UInt16, initial: UInt16) -> UInt16 {
        var crc = initial
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ poly : (crc << 1)
            }
        }
        return crc
    }
}

public struct CZCodec {
    public typealias Checksum = ([UInt8], UInt8) -> UInt8
    private let checksumFunction: Checksum

    public init(checksum: @escaping Checksum = CZChecksum.sumWithReportId) {
        self.checksumFunction = checksum
    }

    public func encode(
        commandType: UInt8,
        command: UInt8,
        payload: [UInt8],
        reportId: UInt8,
        maxPacketSize: Int
    ) -> [[UInt8]] {
        let headerLength = 6
        let maxPayload = max(1, maxPacketSize - headerLength - 1)
        let packetCount = max(1, Int(ceil(Double(payload.count) / Double(maxPayload))))
        var packets: [[UInt8]] = []

        for index in 0..<packetCount {
            let start = index * maxPayload
            let end = min(start + maxPayload, payload.count)
            let chunk = Array(payload[start..<end])
            var bytes: [UInt8] = [
                commandType,
                command,
                0,
                UInt8(packetCount),
                UInt8(index),
                UInt8(chunk.count),
            ]
            bytes.append(contentsOf: chunk)
            while bytes.count < maxPacketSize - 1 {
                bytes.append(0)
            }
            bytes.append(checksumFunction(bytes, reportId))
            packets.append(bytes)
        }
        return packets
    }

    public func decode(packet: [UInt8], reportId: UInt8) throws -> CZPacket {
        guard packet.count >= 7 else {
            throw HIDError.invalidResponse
        }
        let expected = packet[packet.count - 1]
        let actual = checksumFunction(Array(packet.dropLast()), reportId)
        guard expected == actual else {
            throw HIDError.invalidResponse
        }
        let length = Int(packet[5])
        guard length <= packet.count - 7 else {
            throw HIDError.invalidResponse
        }
        let payload = Array(packet[6..<(6 + length)])
        return CZPacket(
            commandType: packet[0],
            command: packet[1],
            packetCount: packet[3],
            packetIndex: packet[4],
            payload: payload
        )
    }

    public func checksum(bytes: [UInt8], reportId: UInt8) -> UInt8 {
        checksumFunction(bytes, reportId)
    }
}
```

This code assumes the checksum is the last byte and the header is `[type, command, 0, packetCount, packetIndex, length]`. The web bundle's `setChecksum` writes the checksum at a fixed `checksumIndex`; if the capture shows a different index, add a `checksumIndex` parameter and adjust `encode`/`decode` to match. Do not guess a different layout when the capture disagrees.

- [ ] **Step 5: Run the checksum probe and pick the matching algorithm**

Run:

```bash
swift test --filter CZCodecTests/testChecksumCandidates -v
```

Expected: the test prints the candidate list and one candidate equals the captured checksum. Note the candidate name.

If none match, extend the candidate list with CRC-16/CCITT-FALSE high byte, CRC-16/MODBUS, and CRC-8/MAXIM (poly `0x31`, reflected) and rerun. Keep the assertion; do not remove it to make the test pass.

- [ ] **Step 6: Use the confirmed checksum**

In `CZCodecTests.testDecodeCapturedRequest`, replace `CZCodec()` with the confirmed candidate:

```swift
let codec = CZCodec(checksum: CZChecksum.crc16LowByte(poly: 0x1021, initial: 0xFFFF))
```

Use the actual candidate from Step 5, not necessarily this example. In Task 8, construct `CZSession` with the same codec.

Run:

```bash
swift test --filter CZCodecTests
```

Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/Protocol Tests/ProtocolTests
git commit -m "feat: implement CZ frame codec from captured frames"
```

---

## Task 8: Add the read-only `info` command

**Files:**
- Create: `Sources/Protocol/CZSession.swift`
- Modify: `Sources/MCHOSECLI/main.swift`
- Test: `Tests/ProtocolTests/CZSessionTests.swift`

**Interfaces:**
- Consumes: `HIDDeviceHandle`, `CZCodec`, captured command ID/payload
- Produces: `CZSession(handle:)`, `.readOnce(commandType:command:payload:reportId:) throws -> [UInt8]`

- [ ] **Step 1: Write the failing test**

Create `Tests/ProtocolTests/CZSessionTests.swift`:

```swift
import XCTest
@testable import Protocol
@testable import HIDTransport

final class CZSessionTests: XCTestCase {
    func testTimeoutDescription() {
        XCTAssertEqual(
            CZSessionError.timeout.localizedDescription,
            "Timed out waiting for a device response"
        )
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --filter CZSessionTests
```

Expected: FAIL, `CZSession` is not defined.

- [ ] **Step 3: Implement the read-only session**

Create `Sources/Protocol/CZSession.swift`:

```swift
import Foundation
import HIDTransport

public enum CZSessionError: Error, LocalizedError {
    case timeout

    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Timed out waiting for a device response"
        }
    }
}

public final class CZSession {
    private let handle: HIDDeviceHandle
    private let codec: CZCodec

    public init(handle: HIDDeviceHandle, codec: CZCodec = CZCodec()) {
        self.handle = handle
        self.codec = codec
    }

    public func readOnce(
        commandType: UInt8,
        command: UInt8,
        payload: [UInt8],
        reportId: UInt8,
        maxPacketSize: Int = 64,
        timeout: TimeInterval = 1.0
    ) throws -> [UInt8] {
        let packets = codec.encode(
            commandType: commandType,
            command: command,
            payload: payload,
            reportId: reportId,
            maxPacketSize: maxPacketSize
        )

        let semaphore = DispatchSemaphore(value: 0)
        var response: [UInt8] = []

        try handle.startInputReports { _, bytes in
            if response.isEmpty {
                response = bytes
                semaphore.signal()
            }
        }

        for packet in packets {
            try handle.setOutputReport(reportId: UInt32(reportId), bytes: packet)
        }

        let result = semaphore.wait(timeout: .now() + timeout)
        handle.stopInputReports()

        guard result == .success else {
            throw CZSessionError.timeout
        }
        return response
    }
}
```

Update `Sources/MCHOSECLI/main.swift` by adding an `info` case before `default`:

```swift
case "info":
    guard arguments.count >= 3,
          let commandType = UInt8(arguments[1], radix: 16),
          let command = UInt8(arguments[2], radix: 16) else {
        print("usage: mchose-cli info <commandType-hex> <command-hex> [reportId-hex]")
        exit(1)
    }
    guard let ref = configurationRef() else {
        print("No MCHOSE configuration interface found.")
        exit(1)
    }
    let reportId = arguments.count >= 4 ? (UInt8(arguments[3], radix: 16) ?? 0) : 0
    let handle = HIDDeviceHandle(device: ref.device)
    do {
        try handle.open()
        // After Task 7 Step 5, construct CZSession with the confirmed checksum codec.
        let session = CZSession(handle: handle)
        let response = try session.readOnce(
            commandType: commandType,
            command: command,
            payload: [],
            reportId: reportId
        )
        print("response: \(Hex.string(response))")
        handle.close()
    } catch {
        print("info failed: \(error.localizedDescription)")
        exit(1)
    }
```

The command type, command ID, and report ID come from Task 6's capture. After Task 7 Step 5, pass the confirmed checksum codec to `CZSession`; do not keep a default checksum that the capture did not confirm.

- [ ] **Step 4: Run the tests and a hardware read**

Run:

```bash
swift test --filter CZSessionTests
swift run mchose-cli info <captured-type> <captured-command> <captured-report-id>
```

Expected: the unit test PASSes. The hardware command prints either a `response:` hex line or `info failed: Timed out waiting for a device response`. A timeout means the command IDs, report ID, or checksum from the capture are not yet correct; fix them from `docs/captures/ace68-phase0.md`, not by guessing.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "feat: add read-only CZ session and info command"
```

---

## Task 9: Extract the Ace 68 Turbo manifest from the web device database

**Files:**
- Create: `Tools/extract-manifest/extract.py`
- Create: `Tools/extract-manifest/test_extract.py`
- Create: `Tools/extract-manifest/fixtures/ace68_snippet.txt`
- Create: `Resources/DeviceManifests/ace68_turbo_16k.json`

**Interfaces:**
- Consumes: `https://www.mchose.com.cn/cizhou/CZ_SHARED_DATA/asset-manifest.json?v=1`
- Produces: `Resources/DeviceManifests/ace68_turbo_16k.json` with fields `id`, `displayName`, `protocolFamily`, `identities`, `configInterface`, `capabilities`, `profileSlots`, `macroSlots`, `layoutAsset`, `lightingMatrix`, `ranges`, `verified`

- [ ] **Step 1: Write the fixture**

Create `Tools/extract-manifest/fixtures/ace68_snippet.txt` with the exact fragment below (copied from the live bundle):

```text
storageKey:"Ace 68 Turbo 16K",name:"Ace 68 Turbo",fullName:"Ace 68 Turbo(16K)",type:211,fwVersion:122,bootUpdateMode:"0x3837_0x3027",hidFilters:[{usagePage:1,usage:0},{usagePage:65280,usage:1,boot:!0}],spread:[{_identity:{vendorId:14391,productId:12326,productName:null,key:"0x3837_0x3026"}}]
```

- [ ] **Step 2: Write the failing test**

Create `Tools/extract-manifest/test_extract.py`:

```python
import json
import pathlib
import unittest

from extract import parse_device_block


class ExtractTests(unittest.TestCase):
    def test_parses_ace68_fixture(self):
        fixture = pathlib.Path(__file__).parent / "fixtures" / "ace68_snippet.txt"
        block = fixture.read_text()

        device = parse_device_block(block)

        self.assertEqual(device["id"], "ace68-turbo-16k")
        self.assertEqual(device["displayName"], "Ace 68 Turbo 16K")
        self.assertEqual(device["protocolFamily"], "cz")
        self.assertEqual(device["identities"][0]["vendorId"], 14391)
        self.assertEqual(device["identities"][0]["productId"], 12326)
        self.assertEqual(device["identities"][1]["productId"], 12327)
        self.assertEqual(device["configInterface"]["usagePage"], 1)
        self.assertEqual(device["configInterface"]["usage"], 0)
        self.assertEqual(device["verified"], True)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
cd ~/mchose-mac/Tools/extract-manifest
python3 -m unittest test_extract.py -v
```

Expected: FAIL, `extract` module or `parse_device_block` is missing.

- [ ] **Step 4: Implement the extractor**

Create `Tools/extract-manifest/extract.py`:

```python
#!/usr/bin/env python3
import json
import re
import sys
import urllib.request

MANIFEST_URL = "https://www.mchose.com.cn/cizhou/CZ_SHARED_DATA/asset-manifest.json?v=1"
BASE_URL = "https://www.mchose.com.cn/cizhou/CZ_SHARED_DATA/"


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read().decode("utf-8", errors="replace")


def parse_device_block(block: str) -> dict:
    def text(name: str) -> str:
        match = re.search(name + r':"([^"]*)"', block)
        if not match:
            raise ValueError(f"missing {name}")
        return match.group(1)

    def number(name: str) -> int:
        match = re.search(name + r':(\d+)', block)
        if not match:
            raise ValueError(f"missing {name}")
        return int(match.group(1))

    boot = re.search(r'bootUpdateMode:"0x([0-9A-Fa-f]+)_0x([0-9A-Fa-f]+)"', block)
    if not boot:
        raise ValueError("missing bootUpdateMode")
    boot_vendor = int(boot.group(1), 16)
    boot_product = int(boot.group(2), 16)

    normal = re.search(
        r'_identity:\{vendorId:(\d+),productId:(\d+)', block
    )
    if not normal:
        raise ValueError("missing normal identity")
    normal_vendor = int(normal.group(1))
    normal_product = int(normal.group(2))

    usage = re.search(
        r'hidFilters:\[\{usagePage:(\d+),usage:(\d+)\}', block
    )
    if not usage:
        raise ValueError("missing hidFilters")
    usage_page = int(usage.group(1))
    usage_id = int(usage.group(2))

    return {
        "id": "ace68-turbo-16k",
        "displayName": text("storageKey"),
        "protocolFamily": "cz",
        "identities": [
            {"vendorId": normal_vendor, "productId": normal_product, "mode": "normal"},
            {"vendorId": boot_vendor, "productId": boot_product, "mode": "boot"},
        ],
        "configInterface": {
            "usagePage": usage_page,
            "usage": usage_id,
            "maxReportSize": 64,
        },
        "capabilities": {
            "magnetic": True,
            "keymap": True,
            "macros": True,
            "socd": True,
            "lighting": True,
            "perKeyLighting": True,
            "gifLighting": False,
            "musicSync": False,
            "battery": False,
        },
        "profileSlots": 0,
        "macroSlots": 0,
        "layoutAsset": "Layouts/ace68_turbo_16k.json",
        "lightingMatrix": {"rows": 0, "cols": 0},
        "ranges": {
            "actuationMm": {"min": 0.0, "max": 0.0, "step": 0.01},
            "rtMm": {"min": 0.0, "max": 0.0, "step": 0.01},
        },
        "verified": True,
        "firmwareVersion": number("fwVersion"),
        "deviceType": number("type"),
    }


def main() -> None:
    manifest = json.loads(fetch(MANIFEST_URL))
    main_js = manifest["entrypoints"]["main"]["assets"]["js"][-1]
    source = fetch(BASE_URL + main_js)

    marker = 'storageKey:"Ace 68 Turbo 16K"'
    index = source.find(marker)
    if index == -1:
        raise SystemExit("Ace 68 Turbo 16K block not found; the bundle may have changed")

    start = source.rfind("{", 0, index)
    block = source[start:start + 5000]
    device = parse_device_block(block)

    output = sys.argv[1] if len(sys.argv) > 1 else "Resources/DeviceManifests/ace68_turbo_16k.json"
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(device, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"wrote {output}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run the test and generate the manifest**

Run:

```bash
cd ~/mchose-mac/Tools/extract-manifest
python3 -m unittest test_extract.py -v
cd ~/mchose-mac
python3 Tools/extract-manifest/extract.py Resources/DeviceManifests/ace68_turbo_16k.json
cat Resources/DeviceManifests/ace68_turbo_16k.json
```

Expected: test PASS (1 test); JSON contains normal identity `14391/12326`, boot identity `14391/12327`, `verified: true`.

The zeros in `profileSlots`, `macroSlots`, `lightingMatrix`, and `ranges` are intentionally unresolved Phase 0 values; fill them from the web UI's device readback in Phase 1. Do not treat them as real limits.

- [ ] **Step 6: Commit**

```bash
git add Tools Resources
git commit -m "feat: extract Ace 68 Turbo device manifest"
```

---

## Task 10: Phase 0 acceptance and findings

**Files:**
- Modify: `docs/captures/ace68-phase0.md`
- Modify: `docs/superpowers/specs/2026-10-18-mchose-mac-design.md` (only the Phase 0 confirmation bullets)
- Modify: `Sources/MCHOSECLI/main.swift` only if the captured command IDs require it

- [ ] **Step 1: Run the full test suite**

Run:

```bash
cd ~/mchose-mac
swift test
```

Expected: all tests PASS.

- [ ] **Step 2: Run the hardware acceptance commands**

Run:

```bash
swift run mchose-cli list
swift run mchose-cli open
swift run mchose-cli info <captured-type> <captured-command> <captured-report-id>
```

Expected:

1. `list` shows `Ace 68 Turbo 16K` with `vid=0x3837 pid=0x3026 usagePage=0x1 usage=0x0 in=64 out=64`.
2. `open` prints `open=0x0 Ace 68 Turbo 16K`.
3. `info` prints a `response:` hex line without any write command being sent. Compare the response payload with the firmware version shown in the web UI and record the version byte offset in the capture file.

- [ ] **Step 3: Record confirmed protocol facts**

Append a “Confirmed” section to `docs/captures/ace68-phase0.md`:

```markdown
## Confirmed

- Report ID used by the native interface:
- Command frame header layout:
- Checksum algorithm:
- Read-info command type/command:
- Response header layout:
- Firmware version offset in response:
```

Fill every line from the capture and the working `info` command. If a line cannot be filled, Phase 0 is not complete.

- [ ] **Step 4: Update the spec's Phase 0 bullets**

In `docs/superpowers/specs/2026-10-18-mchose-mac-design.md`, replace the three “Phase 0 必须确认” bullets with the confirmed values and a note that they were validated on 2026-10-18.

- [ ] **Step 5: Verify no write path exists**

Run:

```bash
grep -R "kIOHIDReportTypeOutput\|setOutputReport" Sources
grep -R "Set\|Reset\|OTA\|boot" Sources/Protocol Sources/MCHOSECLI
```

Expected: `setOutputReport` appears only in `HIDDeviceHandle` (implementation) and `CZSession` (read-only call). There is no code path that sends a `Set`/`Reset`/OTA command. If any exists, delete it before committing.

- [ ] **Step 6: Commit**

```bash
git add docs Sources Resources Tools Tests
git commit -m "chore: complete Phase 0 read-only protocol validation"
```

---

## Phase 0 Exit Criteria

Phase 0 is complete only when all of the following are true:

- [ ] `swift test` passes.
- [ ] `mchose-cli list` finds the Ace 68 Turbo 16K configuration interface.
- [ ] `mchose-cli open` returns `open=0x0`.
- [ ] `mchose-cli info` reads a response from the device without sending any Set/Reset/OTA command.
- [ ] The capture file contains the exact request and response frames.
- [ ] The spec's Phase 0 confirmation bullets are replaced with confirmed values.
- [ ] No write command exists in the Phase 0 code path.

If the `info` command cannot read a response, stop and report the captured request/response hex. Do not proceed to Phase 1 UI work.
