import SwiftUI

struct ServiceIconView: View {
    let name: String
    let catalogId: String?

    var body: some View {
        if let catalogId, let icon = NSImage(named: catalogId) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            InitialsAvatarView(name: name)
        }
    }
}

struct InitialsAvatarView: View {
    let name: String

    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var backgroundColor: Color {
        let hash = abs(name.hashValue)
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange,
            .yellow, .green, .teal, .cyan, .indigo,
        ]
        return colors[hash % colors.count]
    }

    /// The tile hue pushed toward black (light) or white (dark). The raw
    /// system hue on its own 20% tint measured as low as 1.4:1 (yellow).
    private var textColor: Color {
        let base = NSColor(backgroundColor)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? base.blended(withFraction: 0.45, of: .white) ?? base
                : base.blended(withFraction: 0.6, of: .black) ?? base
        })
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor.opacity(0.2))
            Text(initials)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(textColor)
        }
        .frame(width: 20, height: 20)
    }
}
