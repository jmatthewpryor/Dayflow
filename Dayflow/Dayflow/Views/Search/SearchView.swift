import SwiftUI

/// Main search view (non-modal) that appears when search tab is selected
struct SearchView: View {
    @ObservedObject var searchState: SearchState
    @FocusState private var isSearchFieldFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
                .padding(.bottom, 24)

            if let result = searchState.previewResult {
                // Screenshot preview (replaces results)
                screenshotPreview(result: result)
            } else {
                // Search interface
                searchInterface
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            searchState.loadAppsIfNeeded()
            isSearchFieldFocused = true
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - Key Monitor

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape key
                if searchState.previewResult != nil {
                    searchState.closePreview()
                    return nil // Consume the event
                }
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

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search")
                    .font(.custom("InstrumentSerif-Regular", size: 36))
                    .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12))

                Text("Find any moment by searching text on screen")
                    .font(.custom("Nunito", size: 13))
                    .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.6))
            }

            Spacer()

            // Keyboard shortcut hint
            HStack(spacing: 4) {
                Text("⌘K")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.08))
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Search Interface

    private var searchInterface: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Search input
            searchField

            // Filters
            if !searchState.availableApps.isEmpty {
                filtersBar
            }

            // Results or empty state
            resultsContent
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.4))
                .font(.system(size: 16))

            TextField("Search screenshots (use quotes for exact phrase)...", text: $searchState.query)
                .textFieldStyle(.plain)
                .font(.custom("Nunito", size: 15))
                .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12))
                .focused($isSearchFieldFocused)

            if searchState.isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            }

            if !searchState.query.isEmpty {
                Button {
                    searchState.clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.1), lineWidth: 1)
        )
    }

    private var filtersBar: some View {
        HStack(spacing: 12) {
            Menu {
                Button("All Apps") {
                    searchState.selectedAppFilter = nil
                }
                Divider()
                ForEach(searchState.availableApps) { app in
                    Button("\(app.name) (\(app.count))") {
                        searchState.selectedAppFilter = app.bundleId
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedAppName)
                        .font(.custom("Nunito", size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.06))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Spacer()

            if !searchState.results.isEmpty {
                Text("\(searchState.results.count) results")
                    .font(.custom("Nunito", size: 12))
                    .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.5))
            }
        }
    }

    private var selectedAppName: String {
        if let bundleId = searchState.selectedAppFilter,
           let app = searchState.availableApps.first(where: { $0.bundleId == bundleId }) {
            return app.name
        }
        return "All Apps"
    }

    @ViewBuilder
    private var resultsContent: some View {
        if searchState.query.isEmpty {
            emptyState(
                icon: "magnifyingglass",
                title: "Search your screenshots",
                subtitle: "Find any moment by searching text, app names, or window titles"
            )
        } else if searchState.results.isEmpty && !searchState.isLoading {
            emptyState(
                icon: "doc.text.magnifyingglass",
                title: "No results found",
                subtitle: "Try a different search term"
            )
        } else {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)
                ], spacing: 16) {
                    ForEach(searchState.results) { result in
                        SearchResultTile(result: result) {
                            searchState.navigateToResult(result)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.2))
            Text(title)
                .font(.custom("Nunito", size: 16).weight(.semibold))
                .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12))
            Text(subtitle)
                .font(.custom("Nunito", size: 13))
                .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Screenshot Preview

    private func screenshotPreview(result: SearchService.SearchResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            Button {
                searchState.closePreview()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back to results")
                        .font(.custom("Nunito", size: 13))
                }
                .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)

            // Preview content
            ScreenshotPreviewContent(result: result, searchQuery: searchState.query)
        }
    }
}

// MARK: - Search Result Tile (styled for the view)

struct SearchResultTile: View {
    let result: SearchService.SearchResult
    let onSelect: () -> Void

    @State private var thumbnail: NSImage?
    @State private var isHovered = false

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
                ZStack(alignment: .topTrailing) {
                    if let thumbnail = thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.05))
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                    }

                    // URL button - opens URL directly
                    if let urlString = result.browserURL, !urlString.isEmpty {
                        Button {
                            openURL(urlString)
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
                    }
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Metadata
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let appName = result.appName {
                            Text(appName)
                                .font(.custom("Nunito", size: 12).weight(.semibold))
                                .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12))
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(formatTimestamp())
                            .font(.custom("Nunito", size: 11))
                            .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.5))
                    }

                    if let windowTitle = result.windowTitle, !windowTitle.isEmpty {
                        Text(windowTitle)
                            .font(.custom("Nunito", size: 11))
                            .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.5))
                            .lineLimit(1)
                    }

                    if !result.matchedText.isEmpty {
                        Text(result.matchedText.replacingOccurrences(of: "\n", with: " "))
                            .font(.custom("Nunito", size: 11))
                            .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.4))
                            .lineLimit(2)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.04) : Color.white)
                    .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 12 : 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered ? Color(hex: "F96E00").opacity(0.3) : Color.clear, lineWidth: 2)
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

    private func formatTimestamp() -> String {
        let time = Self.timeFormatter.string(from: result.capturedAt)
        let date = Self.dateFormatter.string(from: result.capturedAt)
        return "\(date), \(time)"
    }

    private func loadThumbnail() async {
        let path = result.screenshotPath
        let loaded = await Task.detached(priority: .utility) {
            NSImage(contentsOfFile: path)
        }.value
        await MainActor.run {
            thumbnail = loaded
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
}

// MARK: - Screenshot Preview Content

struct ScreenshotPreviewContent: View {
    let result: SearchService.SearchResult
    let searchQuery: String

    @State private var image: NSImage?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d, yyyy 'at' h:mm:ss a"
        return formatter
    }()

    /// Common stop words (must match SearchService)
    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for",
        "from", "has", "he", "in", "is", "it", "its", "of", "on",
        "or", "that", "the", "to", "was", "were", "will", "with"
    ]

    /// Regions that match the search query (with stop words filtered)
    private var matchingRegions: [SearchService.TextRegion] {
        guard !searchQuery.isEmpty else { return [] }

        // Normalize smart quotes
        let normalized = searchQuery
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        // Check if it's a quoted phrase
        let isPhrase = normalized.hasPrefix("\"") && normalized.hasSuffix("\"") && normalized.count > 2

        if isPhrase {
            let phrase = String(normalized.dropFirst().dropLast())
            guard !phrase.isEmpty else { return [] }

            // First check if any single region contains the entire phrase
            let exactMatches = result.ocrRegions.filter { region in
                region.text.lowercased().contains(phrase)
            }
            if !exactMatches.isEmpty {
                return exactMatches
            }

            // Group regions into lines based on y-coordinate AND x-proximity (same column)
            let lineThreshold: CGFloat = 0.02
            let columnThreshold: CGFloat = 0.25  // Regions must be within 25% x to be same column
            var lines: [[SearchService.TextRegion]] = []

            for region in result.ocrRegions {
                if let lineIdx = lines.firstIndex(where: { line in
                    // Check if this region is close to ANY region in the line
                    return line.contains { existingRegion in
                        let sameY = abs(existingRegion.y - region.y) < lineThreshold
                        let sameColumn = abs(existingRegion.x - region.x) < columnThreshold
                        return sameY && sameColumn
                    }
                }) {
                    lines[lineIdx].append(region)
                } else {
                    lines.append([region])
                }
            }

            // Sort each line by reading order: x (left to right), then y (top to bottom = descending y)
            lines = lines.map { $0.sorted { a, b in
                if abs(a.x - b.x) < 0.05 {
                    // Same column: sort by y descending (top to bottom in Vision coords)
                    return a.y > b.y
                }
                // Different columns: sort by x
                return a.x < b.x
            }}

            // Sort lines by y (top to bottom - higher y first for Vision coords)
            lines.sort { line1, line2 in
                guard let first1 = line1.first, let first2 = line2.first else { return false }
                return first1.y > first2.y
            }

            // Helper to find minimum regions containing phrase
            func findMinimalMatch(in regions: [SearchService.TextRegion]) -> [SearchService.TextRegion]? {
                // Try increasingly larger windows, return first (smallest) that matches
                for windowSize in 1...regions.count {
                    for startIdx in 0...(regions.count - windowSize) {
                        let window = Array(regions[startIdx..<(startIdx + windowSize)])
                        let combinedText = window.map { $0.text.lowercased() }.joined(separator: " ")
                        if combinedText.contains(phrase) {
                            return window
                        }
                    }
                }
                return nil
            }

            // Search for phrase within lines and across adjacent lines
            var matchedRegions: Set<SearchService.TextRegion> = []

            for lineIdx in 0..<lines.count {
                let line = lines[lineIdx]

                // Try to find phrase within this line (find minimal match)
                if let minMatch = findMinimalMatch(in: line) {
                    minMatch.forEach { matchedRegions.insert($0) }
                }

                // Also try combining end of this line with start of next line (for wrapped phrases)
                if lineIdx + 1 < lines.count {
                    let nextLine = lines[lineIdx + 1]
                    let maxFromCurrent = min(3, line.count)
                    let maxFromNext = min(3, nextLine.count)

                    // Build combined region array from end of current + start of next
                    var crossLineRegions: [SearchService.TextRegion] = []
                    crossLineRegions.append(contentsOf: line.suffix(maxFromCurrent))
                    crossLineRegions.append(contentsOf: nextLine.prefix(maxFromNext))

                    if let minMatch = findMinimalMatch(in: crossLineRegions) {
                        minMatch.forEach { matchedRegions.insert($0) }
                    }
                }
            }

            return Array(matchedRegions)

        } else {
            // For regular queries, filter stop words and match individual words
            let queryWords = normalized
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
                .filter { !Self.stopWords.contains($0) }

            guard !queryWords.isEmpty else { return [] }

            return result.ocrRegions.filter { region in
                let regionText = region.text.lowercased()
                return queryWords.contains { word in
                    regionText.contains(word)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header info
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if let appName = result.appName {
                        Text(appName)
                            .font(.custom("Nunito", size: 18).weight(.semibold))
                            .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12))
                    }

                    Text(Self.dateFormatter.string(from: result.capturedAt))
                        .font(.custom("Nunito", size: 13))
                        .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.6))

                    if let windowTitle = result.windowTitle, !windowTitle.isEmpty {
                        Text(windowTitle)
                            .font(.custom("Nunito", size: 12))
                            .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.5))
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    // Open image with default app
                    Button {
                        openFile()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12))
                            .frame(width: 32, height: 32)
                            .background(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Open")

                    // Reveal in Finder
                    Button {
                        revealInFinder()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 0.35, green: 0.22, blue: 0.12))
                            .frame(width: 32, height: 32)
                            .background(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")

                    // Open URL
                    if let url = result.browserURL, !url.isEmpty {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "link")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color(hex: "F96E00"))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Open URL")
                    }
                }
            }

            // Screenshot image with highlight overlay
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        // Use Canvas for direct drawing - no SwiftUI layout issues
                        Canvas { context, size in
                            for region in matchingRegions {
                                // Vision: origin bottom-left, y increases up
                                // Canvas: origin top-left, y increases down
                                let rect = CGRect(
                                    x: region.x * size.width,
                                    y: (1.0 - region.y - region.height) * size.height,
                                    width: region.width * size.width,
                                    height: region.height * size.height
                                )
                                let path = Path(roundedRect: rect, cornerRadius: 3)
                                context.fill(path, with: .color(Color(hex: "F96E00").opacity(0.25)))
                                context.stroke(path, with: .color(Color(hex: "F96E00").opacity(0.6)), lineWidth: 2)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.35, green: 0.22, blue: 0.12).opacity(0.05))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        Task.detached(priority: .userInitiated) {
            let loaded = NSImage(contentsOfFile: result.screenshotPath)
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

    private func revealInFinder() {
        NSWorkspace.shared.selectFile(result.screenshotPath, inFileViewerRootedAtPath: "")
    }

    private func openFile() {
        let url = URL(fileURLWithPath: result.screenshotPath)
        NSWorkspace.shared.open(url)
    }
}

