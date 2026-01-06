import Foundation
import PostHog

enum PostHogAnalytics {
    private static let apiKey = "phc_IrIWnpLM7586BNytoJB8hjI8CWqNTNjEWnumYn4hBD6"

    static func configure() {
        let config = PostHogConfig(apiKey: apiKey, host: "https://us.i.posthog.com")
        PostHogSDK.shared.setup(config)
    }

    static func capture(event: String, properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    static func trackFirstLaunchIfNeeded() {
        let hasLaunchedKey = "posthog_has_tracked_install"

        if !UserDefaults.standard.bool(forKey: hasLaunchedKey) {
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
            capture(event: "app_installed")
        }
    }
}
