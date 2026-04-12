import SwiftUI

struct ServiceIconView: View {
    let name: String
    let catalogId: String?

    var body: some View {
        if let catalogId, NSImage(named: catalogId) != nil {
            Image(nsImage: NSImage(named: catalogId)!)
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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(backgroundColor.opacity(0.2))
            Text(initials)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(backgroundColor)
        }
        .frame(width: 20, height: 20)
    }
}
