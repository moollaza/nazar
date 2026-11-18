import SwiftUI

/// Settings keys and defaults, shared by the Settings toggles and the dashboard.
enum HistorySettings {
    static let stripKey = "showHistoryStrip"
    static let stripDefault = true
    static let incidentFreeKey = "showHistoryIncidentFree"
    static let incidentFreeDefault = false
}

/// What a service row shows of its history.
enum HistoryDisplay: Equatable {
    case hidden
    /// Incident-free percent beside the name, on one line.
    case percent(ServiceHistory)
    /// Strip under the name, with the percent after it when `showPercent`.
    case strip(ServiceHistory, showPercent: Bool)

    init(history: ServiceHistory?, showStrip: Bool, showPercent: Bool) {
        switch (history, showStrip, showPercent) {
        case let (history?, true, showPercent): self = .strip(history, showPercent: showPercent)
        case let (history?, false, true): self = .percent(history)
        default: self = .hidden
        }
    }

    var tileSize: CGFloat {
        if case .strip = self { return HistoryLayout.tallTile }
        return 20
    }

    /// Appended to the row's VoiceOver label.
    var accessibilityText: String {
        switch self {
        case .hidden: return ""
        case .percent(let history): return ", \(history.incidentFreeSummary)"
        case .strip(let history, let showPercent):
            return ", \(history.issueSummary)" + (showPercent ? ", \(history.incidentFreeSummary)" : "")
        }
    }
}

enum HistoryLayout {
    /// Tile size when the strip is on: the height of the name plus the strip.
    static let tallTile: CGFloat = 30
    private static let nameFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
    private static let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    /// Moves the name so its cap top sits 1pt below the tile top.
    static let nameOffset = 1 - (nameFont.ascender - nameFont.capHeight)
    /// Moves the history line so the strip's bottom sits 1pt above the tile
    /// bottom; the percent beside it is taller and centered on the strip.
    static let historyOffset = -1 + ((percentFont.ascender - percentFont.descender) - HistoryStrip.height) / 2
}

/// The row's name, laid out for its history display: plain, with the
/// percent beside it, or above the strip in a block as tall as the tile.
struct HistoryNameColumn<Name: View>: View {
    let display: HistoryDisplay
    @ViewBuilder let name: () -> Name

    var body: some View {
        switch display {
        case .hidden:
            name()
        case .percent(let history):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                name()
                IncidentFreeText(history: history)
            }
        case .strip(let history, let showPercent):
            ZStack(alignment: .topLeading) {
                Color.clear
                name().offset(y: HistoryLayout.nameOffset)
                HStack(spacing: 6) {
                    HistoryStrip(days: history.days)
                        .help(history.issueSummary)
                    if showPercent {
                        IncidentFreeText(history: history)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .offset(y: HistoryLayout.historyOffset)
            }
            .frame(height: HistoryLayout.tallTile)
        }
    }
}

struct IncidentFreeText: View {
    let history: ServiceHistory

    var body: some View {
        Text(history.incidentFreeText)
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(history.incidentFreeSummary)
    }
}

/// 28 day segments, oldest first. A clear day is a faint gray; a day with an
/// incident takes the color of its worst incident.
struct HistoryStrip: View {
    static let height: CGFloat = 6
    let days: [HistorySeverity]

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color(for: day))
                    .frame(width: 3, height: Self.height)
            }
        }
        .accessibilityHidden(true)
    }

    private func color(for day: HistorySeverity) -> Color {
        switch day {
        case .clear: return Color(nsColor: .tertiaryLabelColor).opacity(0.4)
        case .minor: return Color(nsColor: ComponentStatus.partialOutage.color)
        case .major: return Color(nsColor: ComponentStatus.majorOutage.color)
        case .maintenance: return Color(nsColor: ComponentStatus.underMaintenance.color)
        }
    }
}
