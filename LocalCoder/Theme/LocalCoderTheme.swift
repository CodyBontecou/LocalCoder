import SwiftUI

// MARK: - LocalCoder Theme
// Inspired by Teenage Engineering: industrial, utilitarian, monospaced.
// Strict 3-color system: surface, primary, accent.

enum LC {
    // MARK: - Colors

    /// Background / surface color
    static let surface = Color("lcSurface")
    /// Elevated surface (cards, bars)
    static let surfaceElevated = Color("lcSurfaceElevated")
    /// Primary text / foreground
    static let primary = Color("lcPrimary")
    /// Muted text
    static let secondary = Color("lcSecondary")
    /// Accent — the single pop of color
    static let accent = Color("lcAccent")
    /// Borders and dividers
    static let border = Color("lcBorder")
    /// Inverse surface (for user bubbles etc)
    static let inverseSurface = Color("lcInverseSurface")
    /// Destructive actions
    static let destructive = Color("lcDestructive")

    // MARK: - Typography

    /// Display — large titles
    static func display(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// Heading
    static func heading(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .monospaced)
    }

    /// Body text
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    /// Label — small uppercase
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }

    /// Caption / metadata
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    /// Code
    static func code(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32

    // MARK: - Corner Radius

    static let radiusSM: CGFloat = 4
    static let radiusMD: CGFloat = 8
    static let radiusLG: CGFloat = 12

    // MARK: - Border Width

    static let borderWidth: CGFloat = 1
    static let borderWidthThick: CGFloat = 2
}

// MARK: - View Modifiers

struct LCCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(LC.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: LC.radiusMD))
            .overlay(
                RoundedRectangle(cornerRadius: LC.radiusMD)
                    .stroke(LC.border, lineWidth: LC.borderWidth)
            )
    }
}

struct LCUppercaseLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(LC.label())
            .foregroundStyle(LC.secondary)
            .textCase(.uppercase)
            .tracking(1.5)
    }
}

extension View {
    func lcCard() -> some View {
        modifier(LCCardModifier())
    }

    func lcLabel() -> some View {
        modifier(LCUppercaseLabel())
    }
}

// MARK: - Custom Tab Bar

enum LCTab: Int, CaseIterable {
    case chat = 0
    case files = 1
    case git = 2
    case settings = 3

    var title: String {
        switch self {
        case .chat: return "CHAT"
        case .files: return "FILES"
        case .git: return "GIT"
        case .settings: return "SYS"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right"
        case .files: return "folder"
        case .git: return "arrow.triangle.branch"
        case .settings: return "gear"
        }
    }
}

struct LCTabBar: View {
    @Binding var selectedTab: LCTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LCTab.allCases, id: \.rawValue) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: LC.spacingXS) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .regular, design: .monospaced))

                        Text(tab.title)
                            .font(LC.label(9))
                            .tracking(1.2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LC.spacingSM)
                    .foregroundStyle(selectedTab == tab ? LC.accent : LC.secondary)
                }
                .buttonStyle(.plain)

                if tab != LCTab.allCases.last {
                    Rectangle()
                        .fill(LC.border)
                        .frame(width: LC.borderWidth)
                        .padding(.vertical, LC.spacingSM)
                }
            }
        }
        .padding(.top, LC.spacingXS)
        .padding(.bottom, LC.spacingSM)
        .background(LC.surfaceElevated)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(LC.border)
                .frame(height: LC.borderWidth)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Keyboard Accessory Bar (Termius-style)

struct LCAccessoryBar: View {
    @Binding var selectedTab: LCTab
    let onDismissKeyboard: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            // Tab buttons
            ForEach(LCTab.allCases, id: \.rawValue) { tab in
                Button(action: { selectedTab = tab }) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(selectedTab == tab ? LC.accent : Color(UIColor.secondaryLabel))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(.plain)
            }
            
            // Divider
            Rectangle()
                .fill(Color(UIColor.separator))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 4)
            
            // Keyboard dismiss button
            Button(action: onDismissKeyboard) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(UIColor.secondaryLabel))
                    .frame(width: 44, height: 38)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LC.spacingSM)
        .background(Color(red: 0.965, green: 0.949, blue: 0.925)) // #F6F2EC
    }
}

// MARK: - Reusable Components

struct LCStatusDot: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? LC.accent : LC.secondary.opacity(0.4))
            .frame(width: 6, height: 6)
    }
}

struct LCPillButton: View {
    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void

    enum Style {
        case primary, secondary, destructive
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: LC.spacingXS) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Text(title.uppercased())
                    .font(LC.label(11))
                    .tracking(1)
            }
            .padding(.horizontal, LC.spacingMD)
            .padding(.vertical, LC.spacingSM)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: LC.radiusSM))
            .overlay(
                RoundedRectangle(cornerRadius: LC.radiusSM)
                    .stroke(borderColor, lineWidth: LC.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return LC.accent
        case .secondary: return .clear
        case .destructive: return LC.destructive
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return LC.primary
        case .destructive: return .white
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary: return LC.accent
        case .secondary: return LC.border
        case .destructive: return LC.destructive
        }
    }
}
