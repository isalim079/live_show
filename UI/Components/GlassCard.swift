import SwiftUI

/// Reusable glassmorphic container with refined macOS visual styling.
public struct GlassCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
            )
    }
}

/// Compact pill status badge for state visualization.
public struct StatusBadge: View {
    public let text: String
    public let color: Color
    public let icon: String?

    public init(text: String, color: Color = .accentColor, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.18))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}
