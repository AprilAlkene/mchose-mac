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
                Text("RF 版本：\(info.rffwVersion ?? "未识别")")
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
