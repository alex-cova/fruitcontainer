import Foundation
import SwiftUI

extension String {
    static let appearancePreferenceKey = "appearancePreference"
    static let autoUpdateEnabledKey = "autoUpdateEnabled"
    static let containerMetricsRefreshIntervalKey = "containerMetricsRefreshInterval"
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let showMenuBarExtraKey = "showMenuBarExtra"
    static let showSidebarBadgesKey = "showSidebarBadges"
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case automatic
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
