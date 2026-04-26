import SwiftUI
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "ui")

enum FeedbackType: String, CaseIterable {
    case bug = "Bug Report"
    case featureRequest = "Feature Request"
    case other = "Other"

    var issueTag: String {
        switch self {
        case .bug: return "[Bug]"
        case .featureRequest: return "[Feature]"
        case .other: return "[Feedback]"
        }
    }

    var descriptionHint: String {
        switch self {
        case .bug: return "Steps to reproduce, expected vs actual behavior..."
        case .featureRequest: return "Describe your idea and how it would help..."
        case .other: return "Share your thoughts..."
        }
    }
}

struct FeedbackView: View {
    @State private var feedbackType: FeedbackType = .bug
    @State private var title: String = ""
    @State private var description: String = ""
    @State private var submitted = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var macOSVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send Feedback")
                .font(.headline)

            if submitted {
                // Success state
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    Text("Thanks for your feedback!")
                        .font(.headline)
                    Text("A GitHub issue has been opened in your browser.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Send Another") {
                        submitted = false
                        title = ""
                        description = ""
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Feedback type picker
                Picker("Type", selection: $feedbackType) {
                    ForEach(FeedbackType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                // Title field
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)

                // Description editor
                VStack(alignment: .leading, spacing: 4) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $description)
                        .font(.body)
                        .frame(minHeight: 100, maxHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                        .overlay(alignment: .topLeading) {
                            if description.isEmpty {
                                Text(feedbackType.descriptionHint)
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                // System info
                HStack(spacing: 16) {
                    Label("App \(appVersion)", systemImage: "app")
                    Label("macOS \(macOSVersion)", systemImage: "desktopcomputer")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                // Submit button
                HStack {
                    Spacer()
                    Button("Submit") {
                        submitFeedback()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(24)
    }

    private func submitFeedback() {
        let issueTitle = "\(feedbackType.issueTag) \(title)"
        let body = """
        **Type:** \(feedbackType.rawValue)
        **App Version:** \(appVersion)
        **macOS:** \(macOSVersion)

        ## Description
        \(description)
        """

        var components = URLComponents(string: "https://github.com/moollaza/nazar/issues/new")!
        components.queryItems = [
            URLQueryItem(name: "title", value: issueTitle),
            URLQueryItem(name: "body", value: body),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }

        logger.info("Feedback submitted: \(feedbackType.rawValue) - \(title)")
        submitted = true
    }
}
