//
//  MuseOrganizerApp.swift
//  MuseOrganizer
//
//  Created by Sopan Jalkote on 10/24/26.
//

import SwiftUI
import UserNotifications

@main
struct MuseOrganizerApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    private let notifications = NotificationRouter()

    var body: some Scene {
        WindowGroup {
            IntroHost {
                ContentView()
            }
                .environment(model)
                .tint(Palette.accent)
                .task {
                    // Tapping a Muse price alert opens its plan.
                    notifications.open = { [model] id in model.open(planID: id) }
                    UNUserNotificationCenter.current().delegate = notifications
                    model.priceWatch.startPolling { [model] in model.plans }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.priceWatch.scheduleBackgroundRefresh() }
        }
        .backgroundTask(.appRefresh(PriceWatchCenter.refreshTaskID)) {
            let center = await model.priceWatch
            let ids = await model.plans.map(\.id)
            await center.backgroundRefresh(planIDs: ids)
        }
    }
}
