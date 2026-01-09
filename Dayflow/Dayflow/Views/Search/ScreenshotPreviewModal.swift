import SwiftUI
import AppKit

/// Modal to preview a screenshot from search results
struct ScreenshotPreviewModal: View {
    let screenshotPath: String
    let capturedAt: Date
    let appName: String?
    let windowTitle: String?
    let browserURL: String?
    let onDismiss: () -> Void

    @State private var image: NSImage?
    @State private var keyMonitor: Any?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm:ss a"
        return formatter
    }()

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if let appName = appName {
                            Text(appName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        Text(Self.dateFormatter.string(from: capturedAt))
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }

                    Spacer()

                    // Open URL button
                    if let url = browserURL, !url.isEmpty {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Open URL")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                // Screenshot
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(16)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Footer with window title
                if let windowTitle = windowTitle, !windowTitle.isEmpty {
                    Text(windowTitle)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: 1200, maxHeight: 900)
            .background(Color(white: 0.1))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.5), radius: 30)
        }
        .onAppear {
            loadImage()
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private func loadImage() {
        Task.detached(priority: .userInitiated) {
            let loaded = NSImage(contentsOfFile: screenshotPath)
            await MainActor.run {
                image = loaded
            }
        }
    }

    private func openURL(_ urlString: String) {
        var fullURL = urlString
        if !fullURL.hasPrefix("http://") && !fullURL.hasPrefix("https://") {
            fullURL = "https://" + fullURL
        }
        if let url = URL(string: fullURL) {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                onDismiss()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
