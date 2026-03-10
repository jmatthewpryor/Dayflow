import Foundation
import AppKit
import ApplicationServices

/// Captures frontmost application context using NSWorkspace and Accessibility APIs
actor AppContextService {
    static let shared = AppContextService()

    struct AppContext: Sendable {
        let appName: String?
        let bundleId: String?
        let windowTitle: String?
        let browserURL: String?
        let capturedAt: Date

        init(appName: String? = nil, bundleId: String? = nil, windowTitle: String? = nil, browserURL: String? = nil, capturedAt: Date = Date()) {
            self.appName = appName
            self.bundleId = bundleId
            self.windowTitle = windowTitle
            self.browserURL = browserURL
            self.capturedAt = capturedAt
        }
    }

    /// Known browser bundle identifiers
    private let browserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "company.thebrowser.Browser",  // Arc
        "com.operasoftware.Opera",
        "com.vivaldi.Vivaldi"
    ]

    // MARK: - Permission Handling

    /// Check if accessibility permission is granted
    nonisolated static func isAccessibilityEnabled() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt for accessibility permission (shows system dialog)
    nonisolated static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Context Capture

    /// Capture current frontmost app context
    func captureContext() async -> AppContext {
        // Get frontmost application via NSWorkspace (no permission needed)
        guard let frontApp = await MainActor.run(body: {
            NSWorkspace.shared.frontmostApplication
        }) else {
            return AppContext(capturedAt: Date())
        }

        let appName = frontApp.localizedName
        let bundleId = frontApp.bundleIdentifier
        let pid = frontApp.processIdentifier

        var windowTitle: String? = nil
        var browserURL: String? = nil

        // Use Accessibility API if permitted for richer context
        if Self.isAccessibilityEnabled() {
            let axApp = AXUIElementCreateApplication(pid)
            windowTitle = getWindowTitle(from: axApp)

            // Extract browser URL for known browsers
            if let bid = bundleId, browserBundleIds.contains(bid) {
                browserURL = getBrowserURL(from: axApp, bundleId: bid)
            }
        }

        return AppContext(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            browserURL: browserURL,
            capturedAt: Date()
        )
    }

    // MARK: - Accessibility Helpers

    private func getWindowTitle(from axApp: AXUIElement) -> String? {
        var windowValue: AnyObject?
        let windowResult = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue)

        guard windowResult == .success, let window = windowValue else {
            return nil
        }

        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)

        guard titleResult == .success, let title = titleValue as? String else {
            return nil
        }

        return title.isEmpty ? nil : title
    }

    private func getBrowserURL(from axApp: AXUIElement, bundleId: String) -> String? {
        // Different browsers store URL in different places
        // Most use the focused window's document URL or a toolbar text field

        // Try to get the URL from the focused window first
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let window = windowValue else {
            return nil
        }

        let axWindow = window as! AXUIElement

        // Method 1: Try AXDocument attribute (works for some browsers)
        var documentValue: AnyObject?
        if AXUIElementCopyAttributeValue(axWindow, kAXDocumentAttribute as CFString, &documentValue) == .success,
           let documentURL = documentValue as? String {
            return documentURL
        }

        // Method 2: Try to find URL bar in toolbar (Safari, Chrome)
        if let url = findURLInToolbar(window: axWindow, bundleId: bundleId) {
            return url
        }

        return nil
    }

    private func findURLInToolbar(window: AXUIElement, bundleId: String) -> String? {
        // Traverse children to find toolbar (toolbars are child elements with AXToolbar role)
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleValue: AnyObject?
            if AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String {
                if role == kAXToolbarRole as String || role == kAXGroupRole as String {
                    if let url = findURLTextField(in: child, bundleId: bundleId) {
                        return url
                    }
                }
            }
        }

        return nil
    }

    private func findURLTextField(in element: AXUIElement, bundleId: String, depth: Int = 0) -> String? {
        // Limit recursion depth to avoid deep traversal
        guard depth < 10 else { return nil }

        var roleValue: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
        let role = roleValue as? String

        // Check if this is a text field that might contain URL
        if role == kAXTextFieldRole as String || role == kAXComboBoxRole as String {
            // Check role description for URL-related hints
            var descValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleDescriptionAttribute as CFString, &descValue)
            let desc = (descValue as? String)?.lowercased() ?? ""

            // Check identifier/description for URL field indicators
            var identifierValue: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &identifierValue)
            let identifier = (identifierValue as? String)?.lowercased() ?? ""

            let isLikelyURLField = desc.contains("url") ||
                                   desc.contains("address") ||
                                   desc.contains("location") ||
                                   identifier.contains("url") ||
                                   identifier.contains("address") ||
                                   identifier.contains("omnibox")

            if isLikelyURLField {
                var valueAttr: AnyObject?
                if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueAttr) == .success,
                   let value = valueAttr as? String,
                   !value.isEmpty {
                    // Validate it looks like a URL
                    if value.hasPrefix("http://") || value.hasPrefix("https://") || value.contains(".") {
                        return value
                    }
                }
            }
        }

        // Recurse into children
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let url = findURLTextField(in: child, bundleId: bundleId, depth: depth + 1) {
                return url
            }
        }

        return nil
    }
}
