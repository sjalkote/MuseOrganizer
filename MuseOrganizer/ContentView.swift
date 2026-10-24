//
//  ContentView.swift
//  MuseOrganizer
//
//  Created by Sopan Jalkote on 10/24/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Home", systemImage: "house", value: AppModel.AppTab.home) {
                HomeView()
            }
            Tab("Plans", systemImage: "square.stack", value: AppModel.AppTab.plans) {
                PlansView()
            }
            Tab("Shared", systemImage: "tray.and.arrow.down", value: AppModel.AppTab.shared) {
                SharedView()
            }
            .badge(model.pendingShared.count)
            Tab("Apps", systemImage: "link", value: AppModel.AppTab.apps) {
                ConnectionsView()
            }
        }
        .onOpenURL { model.handle($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            model.reloadShared()
        }
    }
}

#Preview {
    ContentView().environment(AppModel())
}
