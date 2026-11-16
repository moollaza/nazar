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

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").filter { $0.first?.isLetter == true || $0.first?.isNumber == true }
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String((words.first ?? Substring(name)).prefix(2)).uppercased()
    }

    private var backgroundColor: Color {
        let hash = abs(name.hashValue)
        let colors: [Color] = [
            .blue, .purple, .pink, .red, .orange,
            .yellow, .green, .teal, .cyan, .indigo,
        ]
        return colors[hash % colors.count]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor.opacity(0.2))
            Text(Self.initials(for: name))
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(backgroundColor)
        }
        .frame(width: 20, height: 20)
    }
}
