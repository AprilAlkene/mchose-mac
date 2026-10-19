import AppKit
import Features
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: DeviceStore
    @State private var section: AppSection = .magnetic

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                store: store,
                section: $section,
                exportConfiguration: exportConfiguration,
                importConfiguration: importConfiguration
            )
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(section: section)
                    .padding(.horizontal, UI.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 14)
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 980, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var page: some View {
        switch section {
        case .magnetic:
            MagneticView(store: store)
        case .keymap:
            KeymapView(store: store)
        case .lighting:
            LightingView(store: store)
        case .perKeyLight:
            PerKeyLightView(store: store)
        case .macros:
            MacroView(store: store)
        case .profiles:
            ProfilesView(store: store)
        case .info:
            DeviceInfoView(info: store.info)
        }
    }

    private func exportConfiguration() {
        let panel = NSSavePanel()
        panel.title = "导出 MCHOSE 配置"
        panel.nameFieldStringValue = "mchose-config.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportConfiguration(to: url)
    }

    private func importConfiguration() {
        let panel = NSOpenPanel()
        panel.title = "导入 MCHOSE 配置"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.importConfiguration(from: url)
    }
}

private struct SidebarView: View {
    @ObservedObject var store: DeviceStore
    @Binding var section: AppSection
    let exportConfiguration: () -> Void
    let importConfiguration: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 14)
            connectionCard
                .padding(.horizontal, 12)
            navigation
                .padding(.top, 16)
            Spacer(minLength: 12)
            footer
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
        }
        .frame(width: UI.sidebarWidth)
        .background(.thinMaterial)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("MCHOSE Mac")
                    .font(.callout.weight(.semibold))
                Text(store.info?.product ?? "Ace 68 Turbo 16K")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var statusColor: Color {
        if store.error != nil { return .red }
        if store.selected != nil { return .green }
        return Color(nsColor: .tertiaryLabelColor)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                StatusDot(color: statusColor)
                Text(store.status)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if store.isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            if let error = store.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            if store.devices.count > 1 {
                Menu(store.selected?.ref.info.product ?? "选择设备") {
                    ForEach(store.devices) { device in
                        Button(device.ref.info.product) { store.select(device) }
                    }
                }
                .font(.caption)
            }
            HStack(spacing: 6) {
                if store.selected == nil {
                    Button("连接") { store.connectSelected() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(store.isBusy)
                } else {
                    Button("断开") { store.disconnectSelected() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.isBusy)
                }
                Button {
                    store.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("扫描设备")
                Spacer()
            }
            if store.writePolicy != .allow {
                Text(store.policyLabel)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private var navigation: some View {
        VStack(spacing: 1) {
            ForEach(AppSection.allCases) { item in
                SidebarItem(section: item, isSelected: section == item) {
                    section = item
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                Button("恢复上次快照") { store.restoreLastSnapshot() }
                    .disabled(store.selected == nil || !store.canWrite)
                Divider()
                Button("导出配置…") { exportConfiguration() }
                    .disabled(store.selected == nil)
                Button("导入配置…") { importConfiguration() }
                    .disabled(store.selected == nil || !store.canWrite)
            } label: {
                Label("快照与配置", systemImage: "ellipsis.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Text("v1 · 本地运行 · 不联网")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
