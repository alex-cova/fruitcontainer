import AppKit
import SwiftUI

struct AppRootView: View {
    let updater: any AppUpdaterProviding
    @AppStorage(.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ContentView(updater: updater)
                    .transition(.opacity)
            } else {
                OnboardingView {
                    withAnimation(.snappy(duration: 0.35, extraBounce: 0)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .animation(.snappy(duration: 0.35, extraBounce: 0), value: hasCompletedOnboarding)
    }
}

#if DEBUG
#Preview {
    AppRootView(updater: DisabledAppUpdater())
        .environmentObject(AppModel.preview)
        .frame(width: 1100, height: 720)
}
#endif
