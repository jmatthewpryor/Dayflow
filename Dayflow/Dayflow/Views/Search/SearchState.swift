import SwiftUI
import Combine

/// Observable state for the search overlay
@MainActor
class SearchState: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published var results: [SearchService.SearchResult] = []
    @Published var isLoading = false
    @Published var selectedAppFilter: String? = nil
    @Published var availableApps: [SearchService.AppInfo] = []
    @Published var previewResult: SearchService.SearchResult? = nil

    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Debounced search (200ms)
        $query
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)

        // Re-search when filter changes
        $selectedAppFilter
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.performSearch(query: self.query)
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func show() {
        isVisible = true
        loadAvailableApps()
    }

    func hide() {
        isVisible = false
        query = ""
        results = []
        selectedAppFilter = nil
    }

    func clearQuery() {
        query = ""
        results = []
    }

    func navigateToResult(_ result: SearchService.SearchResult) {
        // Show screenshot preview modal
        previewResult = result
    }

    func closePreview() {
        previewResult = nil
    }

    func loadAppsIfNeeded() {
        if availableApps.isEmpty {
            loadAvailableApps()
        }
    }

    // MARK: - Private Methods

    private func performSearch(query: String) {
        searchTask?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        isLoading = true

        searchTask = Task {
            let filters = buildFilters()
            let searchResults = await SearchService.shared.search(
                query: query,
                filters: filters
            )

            guard !Task.isCancelled else { return }

            results = searchResults
            isLoading = false
        }
    }

    private func buildFilters() -> SearchService.SearchFilters? {
        var filters = SearchService.SearchFilters()
        var hasFilters = false

        if let appFilter = selectedAppFilter {
            filters.appBundleIds = [appFilter]
            hasFilters = true
        }

        return hasFilters ? filters : nil
    }

    private func loadAvailableApps() {
        Task {
            availableApps = await SearchService.shared.getAvailableApps()
        }
    }
}

// MARK: - Notifications for search

extension Notification.Name {
    static let showSearch = Notification.Name("showSearch")
    static let navigateToScreenshot = Notification.Name("navigateToScreenshot")
}
