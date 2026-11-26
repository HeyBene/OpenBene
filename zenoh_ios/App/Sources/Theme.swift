import SwiftUI

/// Light, paper-like palette shared by the app screens.
enum Theme {
    static let background = Color(red: 0.976, green: 0.976, blue: 0.984)
    static let card = Color.white
    static let border = Color(red: 0.898, green: 0.906, blue: 0.925)
    static let primaryText = Color(red: 0.122, green: 0.145, blue: 0.184)
    static let secondaryText = Color(red: 0.427, green: 0.467, blue: 0.529)
    static let accent = Color(red: 0.157, green: 0.478, blue: 0.851)
    static let teal = Color(red: 0.086, green: 0.639, blue: 0.541)
    static let amber = Color(red: 0.851, green: 0.541, blue: 0.145)
    static let danger = Color(red: 0.855, green: 0.302, blue: 0.302)
    static let softAccent = Color(red: 0.925, green: 0.953, blue: 0.996)
    static let softTeal = Color(red: 0.906, green: 0.973, blue: 0.957)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

struct StatusChip: View {
    var title: String
    var value: String
    var tint: Color
    var isOn: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isOn ? tint : Theme.secondaryText.opacity(0.4))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.primaryText : Theme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(isOn ? tint.opacity(0.09) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isOn ? tint.opacity(0.28) : Theme.border, lineWidth: 1)
        )
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var unit: String?
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String?
    var icon: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.softAccent)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}
