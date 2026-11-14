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

    static let palette: [Color] = [
        .blue, .purple, .pink, .red, .orange,
        .yellow, .green, .teal, .cyan, .indigo,
    ]

    /// FNV-1a over the UTF-8 bytes. `String.hashValue` is seeded per launch,
    /// so it gave a service a different tile color each time the app started.
    static func paletteIndex(for name: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(palette.count))
    }

    private var backgroundColor: Color {
        Self.palette[Self.paletteIndex(for: name)]
    }

    /// The tile hue pushed toward black (light) or white (dark). The raw
    /// system hue on its own 20% tint measured as low as 1.4:1 (yellow).
    private var textColor: Color {
        let base = NSColor(backgroundColor)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? base.blended(withFraction: 0.55, of: .white) ?? base
                : base.blended(withFraction: 0.7, of: .black) ?? base
        })
    }

    /// Measured at 4.4:1 or better against the panel and the row hover
    /// fill for all palette hues in both modes (WCAG non-text needs 3:1).
    private var borderColor: Color {
        let base = NSColor(backgroundColor)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? base.blended(withFraction: 0.3, of: .white) ?? base
                : base.blended(withFraction: 0.5, of: .black) ?? base
        })
    }

    var body: some View {
        ZStack {
            // Opaque base so the row's hover fill can't show through the
            // tint and lower the letter contrast.
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .windowBackgroundColor))
            // The hairline keeps pale tiles (blue, cyan) visible on the grey
            // row hover fill.
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor.opacity(0.2))
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(borderColor, lineWidth: 1)
            Text(initials)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(textColor)
        }
        .frame(width: 20, height: 20)
    }
}
