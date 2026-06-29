//
//  Fruit_ContainerApp.swift
//  Fruit Container
//
//  Created by Alejandro Covarrubias on 25/06/26.
//

import SwiftUI

@main
struct Fruit_ContainerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(.appearancePreferenceKey) private var appearancePreferenceRaw = AppearancePreference.dark.rawValue
    @AppStorage(.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
    @AppStorage(.showMenuBarExtraKey) private var showMenuBarExtra = true
    @State private var appModel: AppModel
    private let refreshController: AppRefreshController

    init() {
        let model = AppModel()
        _appModel = State(initialValue: model)
        refreshController = AppRefreshController(
            appModel: model,
            containerCLIAdapter: AppDependencies.containerCLIAdapter
        )
    }

    var body: some Scene {
        Window("Fruit Container", id: AppSceneID.mainWindow) {
            AppRootView(updater: appDelegate.appUpdater)
                .environmentObject(appModel)
                .environment(\.commandRunner, AppDependencies.commandRunner)
                .environment(\.containerCLIAdapter, AppDependencies.containerCLIAdapter)
                .preferredColorScheme(appearancePreference.colorScheme)
                .onAppear {
                    DispatchQueue.main.async {
                        refreshController.startIfNeeded()
                    }
                }
        }
        .defaultSize(width: 1400, height: 820)
        .defaultLaunchBehavior(shouldPresentMainWindowOnLaunch ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .windowToolbarStyle(.unified)
        .windowResizability(.contentMinSize)
        .commands {
            FruitContainerCommands(
                appModel: appModel,
                updater: appDelegate.appUpdater
            )
        }

        MenuBarExtra(menuBarTitle, systemImage: menuBarSymbol, isInserted: $showMenuBarExtra) {
            MenuBarDashboardView(refreshController: refreshController)
                .environmentObject(appModel)
                .preferredColorScheme(appearancePreference.colorScheme)
        }
        .menuBarExtraStyle(.window)
    }

    private var runningContainerCount: Int {
        appModel.containers.filter { $0.state == .running }.count
    }

    private var menuBarSymbol: String {
        guard let snapshot = appModel.latestSystemHealthSnapshot else {
            return "truck.box"
        }

        switch snapshot.compatibilityReport.state {
        case .unsupported, .unavailable:
            return "exclamationmark.triangle.fill"
        case .untestedNewerMajor:
            return "exclamationmark.triangle"
        case .supported:
            return "truck.box"
        }
    }

    private var menuBarTitle: String {
        runningContainerCount > 0 ? "\(runningContainerCount)" : ""
    }

    private var shouldPresentMainWindowOnLaunch: Bool {
        !hasCompletedOnboarding || !showMenuBarExtra
    }

    private var appearancePreference: AppearancePreference {
        AppearancePreference(rawValue: appearancePreferenceRaw) ?? .dark
    }
}

private struct FruitContainerCommands: Commands {
    @ObservedObject var appModel: AppModel
    let updater: any AppUpdaterProviding
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                appModel.selectedFruitSection = .settings
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: AppSceneID.mainWindow)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates...") {
                updater.checkForUpdates()
            }
            .disabled(!updater.isAvailable)
        }
    }
}
