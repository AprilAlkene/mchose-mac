import SwiftUI

/// The sections shown in the sidebar.
enum AppSection: String, CaseIterable, Identifiable {
    case magnetic
    case keymap
    case lighting
    case perKeyLight
    case macros
    case profiles
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .magnetic: return "磁轴"
        case .keymap: return "改键"
        case .lighting: return "灯效"
        case .perKeyLight: return "逐键灯效"
        case .macros: return "宏"
        case .profiles: return "配置档"
        case .info: return "设备信息"
        }
    }

    var icon: String {
        switch self {
        case .magnetic: return "slider.horizontal.3"
        case .keymap: return "keyboard"
        case .lighting: return "lightbulb"
        case .perKeyLight: return "square.grid.3x3.fill"
        case .macros: return "list.bullet.rectangle"
        case .profiles: return "square.stack.3d.up"
        case .info: return "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .magnetic: return "按键触发行程与快速触发（RT）"
        case .keymap: return "四层键位映射，含 FN 层"
        case .lighting: return "主灯与侧灯的模式、亮度、速度、颜色"
        case .perKeyLight: return "逐键 RGB 静态颜色，需要主灯效 65"
        case .macros: return "16 个共享宏槽位"
        case .profiles: return "板载配置档切换与随应用自动切换"
        case .info: return "固件与设备详细信息"
        }
    }
}

enum UI {
    static let cardRadius: CGFloat = 12
    static let labelWidth: CGFloat = 86
    static let pageWidth: CGFloat = 760
    static let pagePadding: CGFloat = 22
    static let sidebarWidth: CGFloat = 218
}

/// A rounded, material-backed group of controls.
struct Card<Content: View>: View {
    private let title: String?
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: UI.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

/// Label on the left, control on the right.
struct SettingRow<Control: View>: View {
    private let label: String
    private let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: UI.labelWidth, alignment: .leading)
            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Centered, scrollable page container with consistent padding.
struct PageScroll<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: UI.pageWidth, alignment: .leading)
            .padding(.horizontal, UI.pagePadding)
            .padding(.bottom, UI.pagePadding)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct PageHeader: View {
    let section: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.title)
                .font(.title2.weight(.semibold))
            Text(section.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.callout.weight(.medium))
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

struct SidebarItem: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                Text(section.title)
                    .font(.callout)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
