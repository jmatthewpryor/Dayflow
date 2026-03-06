import SwiftUI

/// Individual search result card showing screenshot thumbnail and metadata
struct SearchResultCard: View {
    let result: SearchService.SearchResult
    let onSelect: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    @State private var showURLButton = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Thumbnail
                thumbnailView
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Metadata
                VStack(alignment: .leading, spacing: 4) {
                    // App name & time
                    HStack(spacing: 6) {
                        if let appName = result.appName {
                            Text(appName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(formatTimestamp())
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // Window title
                    if let windowTitle = result.windowTitle, !windowTitle.isEmpty {
                        Text(windowTitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // Matched text with highlighting
                    if !result.matchedText.isEmpty {
                        MatchedTextView(text: result.matchedText)
                            .font(.system(size: 11))
                            .lineLimit(2)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private var thumbnailView: some View {
        ZStack(alignment: .topTrailing) {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.6)
                    }
            }

            // Show "Open URL" button on hover if browser URL exists
            if isHovered, let url = result.browserURL, !url.isEmpty {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Open")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(6)
                .transition(.opacity)
            }
        }
    }

    private func openURL(_ urlString: String) {
        // Ensure URL has scheme
        var fullURL = urlString
        if !fullURL.hasPrefix("http://") && !fullURL.hasPrefix("https://") {
            fullURL = "https://" + fullURL
        }
        if let url = URL(string: fullURL) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Helpers

    private func formatTimestamp() -> String {
        let time = Self.timeFormatter.string(from: result.capturedAt)
        let date = Self.dateFormatter.string(from: result.capturedAt)
        return "\(date), \(time)"
    }

    private func loadThumbnail() async {
        // Load thumbnail on background thread
        let path = result.screenshotPath
        let loaded = await Task.detached(priority: .utility) {
            NSImage(contentsOfFile: path)
        }.value

        await MainActor.run {
            thumbnail = loaded
        }
    }
}

// MARK: - Matched Text View (renders <mark> tags as highlighted)

struct MatchedTextView: View {
    let text: String

    var body: some View {
        attributedText
    }

    private var attributedText: Text {
        var result = Text("")
        var remaining = text

        while let markStart = remaining.range(of: "<mark>") {
            // Add text before mark
            let beforeMark = String(remaining[..<markStart.lowerBound])
            if !beforeMark.isEmpty {
                result = result + Text(beforeMark).foregroundColor(.secondary)
            }

            remaining = String(remaining[markStart.upperBound...])

            // Find closing mark
            if let markEnd = remaining.range(of: "</mark>") {
                let highlighted = String(remaining[..<markEnd.lowerBound])
                result = result + Text(highlighted)
                    .foregroundColor(.orange)
                    .fontWeight(.semibold)
                remaining = String(remaining[markEnd.upperBound...])
            }
        }

        // Add remaining text
        if !remaining.isEmpty {
            result = result + Text(remaining).foregroundColor(.secondary)
        }

        return result
    }
}
