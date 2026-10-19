import Features
import HIDTransport
import SwiftUI

struct DeviceInfoView: View {
    let info: DeviceInfo?

    var body: some View {
        PageScroll {
            if let info {
                Card("设备") {
                    SettingRow("型号") { Text(info.product).font(.callout.weight(.medium)) }
                    SettingRow("固件构建") { Text(info.buildDate).font(.callout) }
                    SettingRow("固件版本") { Text(info.firmwareVersion ?? "未识别").font(.callout) }
                    SettingRow("RF 版本") { Text(info.rffwVersion ?? "未识别").font(.callout) }
                }

                Card("原始信息") {
                    Text(Hex.string(info.rawPayload))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
            } else {
                Card {
                    EmptyState(
                        icon: "info.circle",
                        title: "未连接设备",
                        message: "连接设备后显示固件信息"
                    )
                }
            }
        }
    }
}
