import SwiftUI

struct ServiceIconView: View {
    let name: String
    let catalogId: String?
    var size: CGFloat = 20

    var body: some View {
        if let catalogId, let icon = NSImage(named: catalogId) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size / 5))
                .accessibilityIgnoresInvertColors()
        } else {
            InitialsAvatarView(name: name, size: size)
        }
    }
}

struct InitialsAvatarView: View {
    let name: String
    var size: CGFloat = 20

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String((words.first ?? Substring(name)).prefix(2)).uppercased()
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
                ? base.blended(withFraction: 0.65, of: .white) ?? base
                : base.blended(withFraction: 0.7, of: .black) ?? base
        })
    }

    var body: some View {
        ZStack {
            // Opaque base so the row's hover fill can't show through the
            // tint and lower the letter contrast.
            RoundedRectangle(cornerRadius: size / 5)
                .fill(Color(nsColor: .windowBackgroundColor))
            // A stronger tint than the old 20% so pale hues (blue, cyan)
            // still stand out on the grey row hover fill, without a border.
            RoundedRectangle(cornerRadius: size / 5)
                .fill(backgroundColor.opacity(0.35))
            Text(Self.initials(for: name))
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundColor(textColor)
        }
        .frame(width: size, height: size)
    }
}
