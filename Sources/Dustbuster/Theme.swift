import SwiftUI

enum Theme {
    // Palette taken from the app icon: deep indigo background, hot magenta accent, white.
    static let accent = Color(red: 0.996, green: 0.341, blue: 0.651)
    /// Magenta dark enough to read as text and controls on a light background.
    static let accentDeep = Color(red: 0.76, green: 0.09, blue: 0.37)
    static let ink = Color(red: 0.141, green: 0.075, blue: 0.345)
    static let night = Color(red: 0.20, green: 0.15, blue: 0.42)
    /// Accent for controls and checkmarks.
    static let tint = accentDeep
    static let brandGradient = LinearGradient(
        colors: [accent, Color(red: 0.62, green: 0.25, blue: 0.80)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.22, green: 0.13, blue: 0.50), ink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let aiGradient = LinearGradient(
        colors: [accent, Color(red: 0.56, green: 0.27, blue: 0.86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Tile colors: magentas, violets and indigos, so nothing clashes with the icon.
    static let plum = Color(red: 0.55, green: 0.20, blue: 0.60)
    static let indigo = Color(red: 0.27, green: 0.25, blue: 0.72)
    static let orchid = Color(red: 0.80, green: 0.30, blue: 0.70)
    static let slate = Color(red: 0.36, green: 0.38, blue: 0.52)
    static let mauve = Color(red: 0.50, green: 0.40, blue: 0.72)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardRadius: CGFloat = 16
}

extension SafetyLevel {
    var color: Color {
        switch self {
        case .safe: return .green
        case .caution: return .orange
        case .info: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

extension CleanCategory {
    var symbol: String {
        switch id {
        case "caches": return "internaldrive"
        case "logs": return "doc.text"
        case "claude-scratch": return "sparkles"
        case "claude-edit-backups": return "clock.arrow.circlepath"
        case "claude-temp": return "wind"
        case "codex-temp": return "terminal"
        case "codex-images": return "photo.on.rectangle"
        case "ai-backup-files": return "doc.badge.clock"
        case "browser-history": return "clock"
        case "browser-cookies": return "lock.shield"
        case "mail-downloads": return "envelope"
        case "xcode-derived": return "hammer"
        case "xcode-archives": return "archivebox"
        case "sim-caches": return "iphone"
        case "sim-devices": return "iphone.gen3"
        case "npm", "yarn", "pnpm": return "shippingbox"
        case "homebrew": return "mug"
        case "cocoapods": return "leaf"
        default: return "folder"
        }
    }

    var tint: Color {
        switch id {
        case "caches": return Theme.accentDeep
        case "logs": return Theme.slate
        case "claude-scratch": return Theme.orchid
        case "claude-edit-backups": return Theme.plum
        case "claude-temp": return Theme.mauve
        case "codex-temp": return Theme.indigo
        case "codex-images": return Theme.night
        case "ai-backup-files": return Theme.slate
        case "browser-history", "browser-cookies": return Theme.indigo
        case "mail-downloads": return Theme.mauve
        case "xcode-derived", "xcode-archives": return Theme.night
        case "sim-caches", "sim-devices": return Theme.indigo
        case "npm": return Theme.plum
        case "yarn": return Theme.orchid
        case "pnpm": return Theme.mauve
        case "homebrew": return Theme.slate
        case "cocoapods": return Theme.accentDeep
        default: return Theme.tint
        }
    }
}

// MARK: - Building blocks

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(
                colors: [tint.opacity(0.85), tint],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: tint.opacity(0.3), radius: 4, y: 2)
    }
}

struct SafetyBadge: View {
    let safety: SafetyLevel

    var body: some View {
        Label(safety.rawValue, systemImage: safety.symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(safety.color.opacity(0.15), in: Capsule())
            .foregroundStyle(safety.color)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

/// Header shared by detail pages: icon tile, title, badge and explanation.
struct PageHeader<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var safety: SafetyLevel? = nil
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol, tint: tint, size: 48)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                    if let safety {
                        SafetyBadge(safety: safety)
                    }
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.brandGradient)
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct SelectionCheckbox: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundStyle(isOn ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.secondary.opacity(0.6)))
        }
        .buttonStyle(.plain)
    }
}

/// Floating bottom bar for the destructive "move to Trash" action.
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let bar = HStack(spacing: 12) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

        Group {
            if #available(macOS 26.0, *) {
                bar.glassEffect(.regular, in: Capsule())
            } else {
                bar
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

extension View {
    /// Prominent button style: Liquid Glass on macOS 26, bordered prominent before.
    @ViewBuilder
    func prominentButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Disk usage

struct DiskUsage {
    let total: Int64
    let available: Int64
    var used: Int64 { total - available }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskUsage? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]),
            let total = values.volumeTotalCapacity,
            let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return DiskUsage(total: Int64(total), available: available)
    }
}

let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
}()
